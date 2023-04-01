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
import Combine

typealias Future = LazyFuture

public struct LazyFuture<Output, Failure: Error>: Publisher {
    public typealias Promise = (Result<Output, Failure>) -> Void
    private let task: (@escaping Promise) -> Void

    public init(_ task: @escaping (@escaping Promise) -> Void) {
        self.task = task
    }

    public func receive<S: Subscriber>(subscriber: S) where Failure == S.Failure, Output == S.Input {
        let subscription = FutureSubscription<S>(self, subscriber: subscriber)
        subscriber.receive(subscription: subscription)
    }

    private final class FutureSubscription<S: Subscriber>: Subscription where S.Input == Output, S.Failure == Failure {
        private let publisher: LazyFuture
        private var subscriber: S?

        init(_ publisher: LazyFuture, subscriber: S) {
            self.publisher = publisher
            self.subscriber = subscriber
        }

        func cancel() {
            subscriber = nil
        }

        func request(_ demand: Subscribers.Demand) {
            guard let subscriber = subscriber else { return }
            publisher.task { result in
                switch result {
                case .success(let value):
                    _ = subscriber.receive(value)
                    subscriber.receive(completion: .finished)

                case .failure(let error):
                    subscriber.receive(completion: .failure(error))
                }

                self.subscriber = nil
            }
        }
    }
}
