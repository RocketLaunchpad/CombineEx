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

import XCTest
import Combine
import CombineEx

class CachedSingleValuePublisherTests: XCTestCase {
    func testBasic() {
        var subscriptions = Set<AnyCancellable>()
        var count = 0
        let publish2 = cached(cacheMaxTime: 0, { Just(2) })
        publish2().wrapIfPublisher { $0 }.sink {
            count += 1
            XCTAssertEqual($0, 2)
        }
        .store(in: &subscriptions)

        XCTAssertEqual(count, 1)
    }

    func testAsync() {
        let expectation = XCTestExpectation()
        var subscriptions = Set<AnyCancellable>()

        let publish2 = cached(cacheMaxTime: 0.001, { Just(2).delay(for: .seconds(0.001), scheduler: DispatchQueue.main) })
        var count = 0
        let now = DispatchTime.now()
        let maxCount = 10000
        let delta = 0.001
        for loopCount in 0..<maxCount {
            DispatchQueue.main.asyncAfter(deadline: now + delta * Double(loopCount)) {
                publish2().wrapIfPublisher { $0 }.sink {
                    count += 1
                    XCTAssertEqual($0, 2)
                    if count == maxCount - 1 {
                        expectation.fulfill()
                    }
                }
                .store(in: &subscriptions)
            }
        }

        wait(for: [expectation], timeout: delta * Double(maxCount) + 10)
        XCTAssertEqual(count, maxCount)
    }
}
