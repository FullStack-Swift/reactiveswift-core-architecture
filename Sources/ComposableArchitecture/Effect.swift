import Foundation
import ReactiveSwift
  /// The ``Effect`` type encapsulates a unit of work that can be run in the outside world, and can
  /// feed data back to the ``Store``. It is the perfect place to do side effects, such as network
  /// requests, saving/loading from disk, creating timers, interacting with dependencies, and more.
  ///
  /// Effects are returned from reducers so that the ``Store`` can perform the effects after the
  /// reducer is done running. It is important to note that ``Store`` is not thread safe, and so all
  /// effects must receive values on the same thread, **and** if the store is being used to drive UI
  /// then it must receive values on the main thread.
  ///
  /// An effect simply wraps a `Publisher` value and provides some convenience initializers for
  /// constructing some common types of effects.
public typealias Effect<Value, Error: Swift.Error> = SignalProducer<Value, Error>

extension Effect {
  
    /// An effect that does nothing and completes immediately. Useful for situations where you must
    /// return an effect, but you don't need to do anything.
  public static var none: Self {
    .empty
  }
  
    /// Creates an effect that can supply a single value asynchronously in the future.
    ///
    /// This can be helpful for converting APIs that are callback-based into ones that deal with
    /// ``Effect``s.
    ///
    /// For example, to create an effect that delivers an integer after waiting a second:
    ///
    /// ```swift
    /// Effect<Int, Never>.future { callback in
    ///   DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    ///     callback(.success(42))
    ///   }
    /// }
    /// ```
    ///
    /// Note that you can only deliver a single value to the `callback`. If you send more they will be
    /// discarded:
    ///
    /// ```swift
    /// Effect<Int, Never>.future { callback in
    ///   DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    ///     callback(.success(42))
    ///     callback(.success(1729)) // Will not be emitted by the effect
    ///   }
    /// }
    /// ```
    ///
    ///  If you need to deliver more than one value to the effect, you should use the ``Effect``
    ///  initializer that accepts a ``Subscriber`` value.
    ///
    /// - Parameter attemptToFulfill: A closure that takes a `callback` as an argument which can be
    ///   used to feed it `Result<Output, Failure>` values.
  public static func future(
    _ attemptToFulfill: @escaping (@escaping (Result<Value, Error>) -> Void) -> Void
  ) -> Effect {
    SignalProducer { observer, _ in
      attemptToFulfill { result in
        switch result {
        case let .success(value):
          observer.send(value: value)
          observer.sendCompleted()
        case let .failure(error):
          observer.send(error: error)
        }
      }
    }
  }
  
    /// Initializes an effect that lazily executes some work in the real world and synchronously sends
    /// that data back into the store.
    ///
    /// For example, to load a user from some JSON on the disk, one can wrap that work in an effect:
    ///
    /// ```swift
    /// Effect<User, Error>.result {
    ///   let fileUrl = URL(
    ///     fileURLWithPath: NSSearchPathForDirectoriesInDomains(
    ///       .documentDirectory, .userDomainMask, true
    ///     )[0]
    ///   )
    ///   .appendingPathComponent("user.json")
    ///
    ///   let result = Result<User, Error> {
    ///     let data = try Data(contentsOf: fileUrl)
    ///     return try JSONDecoder().decode(User.self, from: $0)
    ///   }
    ///
    ///   return result
    /// }
    /// ```
    ///
    /// - Parameter attemptToFulfill: A closure encapsulating some work to execute in the real world.
    /// - Returns: An effect.
  public static func result(_ attemptToFulfill: @escaping () -> Result<Value, Error>) -> Self {
    return self.init(result: attemptToFulfill())
  }
    /// Initializes an effect from a callback that can send as many values as it wants, and can send
    /// a completion.
    ///
    /// This initializer is useful for bridging callback APIs, delegate APIs, and manager APIs to the
    /// ``Effect`` type. One can wrap those APIs in an Effect so that its events are sent through the
    /// effect, which allows the reducer to handle them.
    ///
    /// For example, one can create an effect to ask for access to `MPMediaLibrary`. It can start by
    /// sending the current status immediately, and then if the current status is `notDetermined` it
    /// can request authorization, and once a status is received it can send that back to the effect:
    ///
    /// ```swift
    /// Effect.run { subscriber in
    ///   subscriber.send(MPMediaLibrary.authorizationStatus())
    ///
    ///   guard MPMediaLibrary.authorizationStatus() == .notDetermined else {
    ///     subscriber.send(completion: .finished)
    ///     return AnyCancellable {}
    ///   }
    ///
    ///   MPMediaLibrary.requestAuthorization { status in
    ///     subscriber.send(status)
    ///     subscriber.send(completion: .finished)
    ///   }
    ///   return AnyCancellable {
    ///     // Typically clean up resources that were created here, but this effect doesn't
    ///     // have any.
    ///   }
    /// }
    /// ```
    ///
    /// - Parameter work: A closure that accepts a ``Subscriber`` value and returns a cancellable.
    ///   When the ``Effect`` is completed, the cancellable will be used to clean up any resources
    ///   created when the effect was started.
  public static func run(
  ) -> Self {
    fatalError()
  }
  
    /// Concatenates a variadic list of effects together into a single effect, which runs the effects
    /// one after the other.
    ///
    /// - Warning: Combine's `Publishers.Concatenate` operator, which this function uses, can leak
    ///   when its suffix is a `Publishers.MergeMany` operator, which is used throughout the
    ///   Composable Architecture in functions like ``Reducer/combine(_:)-1ern2``.
    ///
    ///   Feedback filed: <https://gist.github.com/mbrandonw/611c8352e1bd1c22461bd505e320ab58>
    ///
    /// - Parameter effects: A variadic list of effects.
    /// - Returns: A new effect
  public static func concatenate(_ effects: Effect...) -> Effect {
    .concatenate(effects)
  }
  
    /// Concatenates a collection of effects together into a single effect, which runs the effects one
    /// after the other.
    ///
    /// - Warning: Combine's `Publishers.Concatenate` operator, which this function uses, can leak
    ///   when its suffix is a `Publishers.MergeMany` operator, which is used throughout the
    ///   Composable Architecture in functions like ``Reducer/combine(_:)-1ern2``.
    ///
    ///   Feedback filed: <https://gist.github.com/mbrandonw/611c8352e1bd1c22461bd505e320ab58>
    ///
    /// - Parameter effects: A collection of effects.
    /// - Returns: A new effect
  public static func concatenate<C: Collection>(
    _ effects: C
  ) -> Effect where C.Element == Effect {
    guard let first = effects.first else { return .none }
    return effects
      .dropFirst()
      .reduce(into: first) { effects, effect in
        effects = effects.concat(effect)
      }
  }
  
    /// Merges a variadic list of effects together into a single effect, which runs the effects at the
    /// same time.
    ///
    /// - Parameter effects: A list of effects.
    /// - Returns: A new effect
  public static func merge(
    _ effects: Effect...
  ) -> Effect {
    .merge(effects)
  }
  
    /// Merges a sequence of effects together into a single effect, which runs the effects at the same
    /// time.
    ///
    /// - Parameter effects: A sequence of effects.
    /// - Returns: A new effect
  public static func merge<S: Sequence>(_ effects: S) -> SignalProducer<Value, Error> where S.Element == Effect {
    return SignalProducer<S.Iterator.Element, Never>(effects).flatten(.merge)
  }
  
    /// Creates an effect that executes some work in the real world that doesn't need to feed data
    /// back into the store.
    ///
    /// - Parameter work: A closure encapsulating some work to execute in the real world.
    /// - Returns: An effect.
  public static func fireAndForget(_ work: @escaping () -> Void) -> Effect {
    .deferred { () -> SignalProducer<Value, Error> in
      work()
      return .empty
    }
  }
  public static func deferred(_ createProducer: @escaping () -> SignalProducer<Value, Error>)
  -> SignalProducer<Value, Error>
  {
    Effect<Void, Error>(value: ())
      .flatMap(.merge, createProducer)
  }
  
    /// Transforms all elements from the upstream effect with a provided closure.
    ///
    /// - Parameter transform: A closure that transforms the upstream effect's output to a new output.
    /// - Returns: A publisher that uses the provided closure to map elements from the upstream effect
    ///   to new elements that it then publishes.
    //MARK:   already in SignalProducer
    //    public func map<T>(_ transform: @escaping (Value) -> T) -> Effect<T, Error> {
    //      return self.map(transform)
    //    }
}

extension Effect where Error == Swift.Error {
  /// Initializes an effect that lazily executes some work in the real world and synchronously sends
  /// that data back into the store.
  ///
  /// For example, to load a user from some JSON on the disk, one can wrap that work in an effect:
  ///
  /// ```swift
  /// Effect<User, Error>.catching {
  ///   let fileUrl = URL(
  ///     fileURLWithPath: NSSearchPathForDirectoriesInDomains(
  ///       .documentDirectory, .userDomainMask, true
  ///     )[0]
  ///   )
  ///   .appendingPathComponent("user.json")
  ///
  ///   let data = try Data(contentsOf: fileUrl)
  ///   return try JSONDecoder().decode(User.self, from: $0)
  /// }
  /// ```
  ///
  /// - Parameter work: A closure encapsulating some work to execute in the real world.
  /// - Returns: An effect.
  public static func catching(_ work: @escaping () throws -> Value) -> Self {
    .future { $0(Result { try work() }) }
  }
}

extension SignalProducer {
    /// Turns any publisher into an ``Effect``.
    ///
    /// This can be useful for when you perform a chain of publisher transformations in a reducer, and
    /// you need to convert that publisher to an effect so that you can return it from the reducer:
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return fetchUser(id: 1)
    ///     .filter(\.isAdmin)
    ///     .eraseToEffect()
    /// ```
    ///
    /// - Returns: An effect that wraps `self`.
  public func eraseToEffect() -> Self {
    self
  }
  
    /// Turns any publisher into an ``Effect`` that cannot fail by wrapping its output and failure in
    /// a result.
    ///
    /// This can be useful when you are working with a failing API but want to deliver its data to an
    /// action that handles both success and failure.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return environment.fetchUser(id: 1)
    ///     .catchToEffect()
    ///     .map(ProfileAction.userResponse)
    /// ```
    ///
    /// - Returns: An effect that wraps `self`.
  public func catchToEffect() -> Effect<Result<Value, Error>, Never> {
    self.map(Result<Value, Error>.success)
      .flatMapError { Effect<Result<Value, Error>, Never>(value: Result.failure($0)) }
  }
  
    /// Turns any publisher into an ``Effect`` that cannot fail by wrapping its output and failure
    /// into a result and then applying passed in function to it.
    ///
    /// This is a convenience operator for writing ``Effect/catchToEffect()`` followed by a
    /// ``Effect/map(_:)``.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return environment.fetchUser(id: 1)
    ///     .catchToEffect(ProfileAction.userResponse)
    /// ```
    ///
    /// - Parameters:
    ///   - transform: A mapping function that converts `Result<Output,Failure>` to another type.
    /// - Returns: An effect that wraps `self`.
  public func catchToEffect<T>(
    _ transform: @escaping (Result<Value, Error>) -> T
  ) -> Effect<T, Never> {
    self
      .map { transform(.success($0)) }
      .flatMapError { Effect<T, Never>(value: transform(.failure($0))) }
  }
  
    /// Turns any publisher into an ``Effect`` for any output and failure type by ignoring all output
    /// and any failure.
    ///
    /// This is useful for times you want to fire off an effect but don't want to feed any data back
    /// into the system. It can automatically promote an effect to your reducer's domain.
    ///
    /// ```swift
    /// case .buttonTapped:
    ///   return analyticsClient.track("Button Tapped")
    ///     .fireAndForget()
    /// ```
    ///
    /// - Parameters:
    ///   - outputType: An output type.
    ///   - failureType: A failure type.
    /// - Returns: An effect that never produces output or errors.
  public func fireAndForget<NewValue, NewError>(
    outputType: NewValue.Type = NewValue.self,
    failureType: NewError.Type = NewError.self
  ) -> Effect<NewValue, NewError> {
    self.flatMapError { _ in .empty }
    .flatMap(.latest) { _ in
    .empty
    }
  }
}

extension Effect where Self.Error == Never {
  
    /// Assigns each element from a observable to a property on an object.
    ///
    /// - Parameters:
    ///   - to: A key path that indicates the property to assign. See Key-Path Expression in The Swift Programming Language to learn how to use key paths to specify a property of an object.
    ///   - object: The object that contains the property. The subscriber assigns the object’s property every time it receives a new value.
    /// - Returns: An Disposable instance. Call dispose() on this instance when you no longer want the publisher to automatically assign the property. Deinitializing this instance will also dispose automatic assignment.
  @discardableResult
  public func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Self.Value>, on object: Root)
  -> Disposable
  {
    self.startWithValues { value in
      object[keyPath: keyPath] = value
    }
  }
}
