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

public protocol Command {
    func run<S>(state: () -> S, dispatch: @escaping DispatchFunction)
}

//extension Command {
//
//    func merge(_ commands: [Self]) {
//        commands.reduce(self) { (_, c) in
//            c.run(state: <#T##() -> Self.State#>, dispatch: <#T##DispatchFunction##DispatchFunction##(Action) -> Void#>)
//        }
//        run(state: <#T##() -> State#>, dispatch: <#T##DispatchFunction##DispatchFunction##(Action) -> Void#>)
//    }
//}

public let asyncActionQueue = DispatchQueue(label: "fun.thrillerone.www.tflux.asyncActionQueue")
public protocol Action { }
public protocol AsyncAction: Action {
    func execute(state: FluxState?, dispatch: @escaping DispatchFunction)
}

//public protocol Reducer {
//    func execute<S: State>(state: S, action: Action) -> S
//}

public typealias Reducer<S: FluxState> = (_ state: S, _ action: Action) -> (state: S, command: Command?)

public typealias DispatchFunction = (Action) -> Void
public typealias Middleware<S> = (@escaping DispatchFunction, @escaping () -> S?) -> (@escaping DispatchFunction) -> DispatchFunction

private let asyncActionMiddleware: Middleware<FluxState> = { dispatch, state in
    return { next in
        return { action in
            
            // execute reducer
            next(action)
            
            if let a = action as? AsyncAction {
                asyncActionQueue.async {
                    a.execute(state: state(), dispatch: dispatch)
                }
            }
        }
    }
}

private let loggingMiddleware: Middleware<FluxState> = { dispatch, getState in
    return { next in
        return { action in
            #if DEBUG
            let name = __dispatch_queue_get_label(nil)
            let queueName = String(cString: name, encoding: .utf8)
            print("#Action: \(String(reflecting: type(of: action))) on queue: \(queueName ?? "??")")
            #endif
            return next(action)
        }
    }
}

@available(OSX 10.15, *)
final public class Store<S: FluxState>: ObservableObject {
    
    @Published public var state: S
    
    private let reducer: Reducer<S>
    private var dispatcher: DispatchFunction!
    
    private lazy var reducerDispatch: DispatchFunction = { [unowned self] in
        
        let result = self.reducer(self.state, $0)
        
        self.state = result.state
        result.command?.run(state: { result.state }, dispatch: self.dispatcher)
    }
    
    public init(reducer: @escaping Reducer<S>,
                middleware: [Middleware<S>] = [],
                state: S) {
        self.state = state
        self.reducer = reducer
        
        var m = middleware
        m.append(contentsOf: [asyncActionMiddleware, loggingMiddleware])
        dispatcher = m.reversed().reduce(reducerDispatch) { dispatchFunc, middleware in
            
            let dispatch: DispatchFunction = { [weak self] in self?.dispatch(action: $0) }
            let state = { [weak self] in self?.state }
            return middleware(dispatch, state)(dispatchFunc) }
    }
    
    public func dispatch(action: Action) { DispatchQueue.main.async { self.dispatcher(action) } }
    
}

