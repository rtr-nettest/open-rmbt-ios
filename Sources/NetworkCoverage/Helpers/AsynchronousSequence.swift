//
//  AsynchronousSequence.swift
//  RMBT
//
//  Created by Jiri Urbasek on 17.01.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

// https://forums.swift.org/t/type-erasure-of-asyncsequences/66547/3

protocol AsynchronousSequence<Element>: AsyncSequence {}

struct _AsyncSequenceWrapper<Base: AsyncSequence>: AsynchronousSequence {
    
    typealias Element = Base.Element
    typealias AsyncIterator = Base.AsyncIterator
    
    var base: Base
    
    func makeAsyncIterator() -> AsyncIterator {
        base.makeAsyncIterator()
    }
}

extension AsyncSequence {
    func asOpaque() -> some AsynchronousSequence<Element> {
        _AsyncSequenceWrapper(base: self)
    }
}
