//
//  TFlux.swift
//  TFlux
//
//  Created by Thriller on 2020/1/21.
//  Copyright © 2020 Thriller. All rights reserved.
//

import Foundation
import Combine

public protocol FluxState { }

//public protocol Command {
//
//    associatedtype State
//
//    func run(state: () -> State, dispatch: @escaping DispatchFunction)
//}

public protocol Action { }
public protocol AsyncAction: Action {
    mutating func execute(state: FluxState?, dispatch: @escaping DispatchFunction)
}

//public protocol Reducer {
//    func execute<S: State>(state: S, action: Action) -> S
//}

public typealias Reducer<S: FluxState> = (_ state: S, _ action: Action) -> S

public typealias DispatchFunction = (Action) -> Void
public typealias Middleware<S> = (@escaping DispatchFunction, @escaping () -> S?) -> (@escaping DispatchFunction) -> DispatchFunction

public let asyncActionMiddleware: Middleware<FluxState> = { dispatch, state in
    return { next in
        return { action in
            
            // execute reducer
            next(action)
            
            if var a = action as? AsyncAction {
                a.execute(state: state(), dispatch: dispatch)
            }
        }
    }
}

@available(OSX 10.15, *)
final public class Store<S: FluxState>: ObservableObject {
    
    @Published public var state: S
    
    private let reducer: Reducer<S>
    private var dispatcher: DispatchFunction!
    
    private lazy var reducerDispatch: DispatchFunction = { [unowned self] action in

        let s = self.reducer(self.state, action)
        
        DispatchQueue.main.async {
            self.state = s
        }
    }
    
    public init(reducer: @escaping Reducer<S>,
                middleware: [Middleware<S>] = [],
                state: S) {
        self.state = state
        self.reducer = reducer
        
        var m = middleware
        m.append(asyncActionMiddleware)
        dispatcher = m.reversed()
            .reduce(reducerDispatch) { dispatchFunc, middleware in
                
                let dispatch: DispatchFunction = { [weak self] in self?.dispatcher($0) }
                let state = { [weak self] in self?.state }
                return middleware(dispatch, state)(dispatchFunc) }
    }
    
    public func dispatch(action: Action) {
        
        self.dispatcher(action)
    }
    
}

