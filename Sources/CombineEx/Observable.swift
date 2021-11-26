//
//  Observable.swift
//  Rocket Insights
//
//  Created by Ilya Belenkiy on 10/8/21.
//

import Combine

public class ObservableValue<T>: ObservableObject {
    @Published public private(set) var value: T

    public init(_ value: T) {
        self.value = value
    }

    public func update(_ newValue: T) {
        value = newValue
    }
}

extension ObservableValue where T: Equatable {
    public func maybeUpdate(_ newValue: T) {
        if value != newValue {
            value = newValue
        }
    }
}

extension ObservableValue: Identifiable where T: Identifiable {
    public var id: T.ID {
        value.id
    }
}

extension ObservableValue: Equatable {
    public static func == (lhs: ObservableValue, rhs: ObservableValue) -> Bool {
        lhs === rhs
    }
}

extension ObservableValue: Hashable where T: Identifiable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ObservableValue {
    convenience public init<W>() where T == W? {
        self.init(nil)
    }
}
