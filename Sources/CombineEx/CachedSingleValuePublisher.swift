//
// Copyright (c) 2023 DEPT Digital Products, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import Foundation
import FoundationEx
import Combine

private struct CachedValue<T> {
    let value: T
    let timestamp: Date
}

// It's easy to make CachedSingleValuePublisher conform to the Publisher protocol, but this
// would lose the benefit of doing something special in the case when the data is cached and
// is available simultaneously. For example, we might want to show a spinner only if the data
// is not cached. Calling AppFlow.run() with this publisher will instead always show a spinner.
//
// Use `unwrap` to get access to the Publisher API. Using the identity transform will
// ensure that the resulting publisher will do the same thing whether the data is cached or not.
public enum CachedSingleValuePublisher<T, E: Error> {
    case cached(T)
    case publisher(AnySingleValuePublisher<T, E>)

    public init(value: T) {
        self = .cached(value)
    }

    public init(error: E) {
        self = .publisher(Fail<T, E>(error: error).eraseType())
    }

    public var cachedValue: T? {
        switch self {
        case .cached(let value):
            return value
        case .publisher:
            return nil
        }
    }

    public func map<U>(_ transform: @escaping (T) -> U) -> CachedSingleValuePublisher<U, E> {
        switch self {
        case .cached(let value):
            return .cached(transform(value))
        case .publisher(let publisher):
            return .publisher(publisher.map(transform).eraseType())
        }
    }

    public func mapError<E2>(_ transform: @escaping (E) -> E2) -> CachedSingleValuePublisher<T, E2> {
        switch self {
        case .cached(let value):
            return .cached(value)
        case .publisher(let publisher):
            return .publisher(publisher.mapError(transform).eraseType())
        }
    }

    public func addErrorType<E2: Error>(_ type: E2.Type) -> CachedSingleValuePublisher<T, E2> where E == Never {
        mapError { _ -> E2 in }
    }

    public func flatMap<U>(_ transform: @escaping (T) -> CachedSingleValuePublisher<U, E>) -> CachedSingleValuePublisher<U, E> {
        switch self {
        case .cached(let value):
            return transform(value)
        case .publisher(let publisher):
            return .publisher(
                publisher.flatMapLatest { value -> AnySingleValuePublisher<U, E> in
                    switch transform(value) {
                    case .cached(let value2):
                        return Just(value2).addErrorType(E.self).eraseType()
                    case .publisher(let publisher2):
                        return publisher2
                    }
                }
                .eraseType()
            )
        }
    }

    public func zip<U>(_ other: CachedSingleValuePublisher<U, E>) -> CachedSingleValuePublisher<(T, U), E> {
        switch (self, other) {
        case (.cached(let value1), .cached(let value2)):
            return .cached((value1, value2))
        default:
            return .publisher(unwrap().zip(other.unwrap()).eraseType())
        }
    }

    public func sideEffect( _ f: @escaping (T) -> Void) -> CachedSingleValuePublisher {
        switch self {
        case .cached(let value):
            f(value)
            return .cached(value)
        case .publisher(let publisher):
            return .publisher(publisher.sideEffect(f).eraseType())
        }
    }

    public func replaceError(with value: T) -> CachedSingleValuePublisher<T, Never> {
        switch self {
        case .cached(let value):
            return .cached(value)
        case .publisher(let publisher):
            return .publisher(publisher.replaceError(with: value).eraseType())
        }
    }

    public func wrapIfPublisher<OutputError: Error>(transform: (AnySingleValuePublisher<T, E>) -> AnySingleValuePublisher<T, OutputError>)
    -> AnySingleValuePublisher<T, OutputError>
    {
        switch self {
        case .cached(let value):
            return Just(value).addErrorType(OutputError.self).eraseType()
        case .publisher(let publisher):
            return transform(publisher)
        }
    }

    public func unwrap() -> AnySingleValuePublisher<T, E> {
        wrapIfPublisher { $0 }
    }
}

public typealias CachedSingleValuePublisherFunc<T, E: Error> = () -> CachedSingleValuePublisher<T, E>

private struct SharedData<P: SingleValuePublisher> {
    var cachedValue: CachedValue<P.Output>?
    var publisher: AnySingleValuePublisher<P.Output, P.Failure>?
}

public func cached<P: SingleValuePublisher>(
    cacheMaxTime: TimeInterval,
    value: P.Output? = nil,
    _ f: @escaping () -> P
)
-> CachedSingleValuePublisherFunc<P.Output, P.Failure>
{
    let cachedValue: CachedValue<P.Output>? = value.map { .init(value: $0, timestamp: CombineEx.env.now()) }
    let sharedData = Locked<SharedData<P>>(.init(cachedValue: cachedValue, publisher: nil))
    return {
        let now = CombineEx.env.now()
        let sharedDataValue = sharedData.value
        if let cachedValue = sharedDataValue.cachedValue {
            let time = now.timeIntervalSince(cachedValue.timestamp)
            if time < cacheMaxTime {
                return .cached(cachedValue.value)
            }
        }

        return sharedData.access { unlocked in
            unlocked.cachedValue = nil
            if let publisher = unlocked.publisher {
                return .publisher(publisher)
            }
            let publisher = f()
                .sideEffect { value in
                    sharedData.access {
                        $0 = .init(
                            cachedValue: .init(value: value, timestamp: Date()),
                            publisher: nil
                        )
                    }
                }
                .catch { error -> AnySingleValuePublisher<P.Output, P.Failure> in
                    sharedData.access {
                        $0 = .init(
                            cachedValue: nil,
                            publisher: nil
                        )
                    }
                    return Fail(error: error).eraseType()
                }
                .share()
                .eraseType()
            unlocked.publisher = publisher
            return .publisher(publisher)
        }
    }
}
