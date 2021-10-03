import ReactiveSwift

  /// A ``ViewStore`` is an object that can observe state changes and send actions. They are most
  /// commonly used in views, such as SwiftUI views, UIView or UIViewController, but they can be
  /// used anywhere it makes sense to observe state and send actions.
  ///
  /// In SwiftUI applications, a ``ViewStore`` is accessed most commonly using the ``WithViewStore``
  /// view. It can be initialized with a store and a closure that is handed a view store and must
  /// return a view to be rendered:
  ///
  /// ```swift
  /// var body: some View {
  ///   WithViewStore(self.store) { viewStore in
  ///     VStack {
  ///       Text("Current count: \(viewStore.count)")
  ///       Button("Increment") { viewStore.send(.incrementButtonTapped) }
  ///     }
  ///   }
  /// }
  /// ```
  ///
  /// In UIKit applications a ``ViewStore`` can be created from a ``Store`` and then subscribed to for
  /// state updates:
  ///
  /// ```swift
  /// let store: Store<State, Action>
  /// let viewStore: ViewStore<State, Action>
  ///
  /// init(store: Store<State, Action>) {
  ///   self.store = store
  ///   self.viewStore = ViewStore(store)
  /// }
  ///
  /// func viewDidLoad() {
  ///   super.viewDidLoad()
  ///
  ///   self.viewStore.publisher.count
  ///     .sink { [weak self] in self?.countLabel.text = $0 }
  ///     .store(in: &self.cancellables)
  /// }
  ///
  /// @objc func incrementButtonTapped() {
  ///   self.viewStore.send(.incrementButtonTapped)
  /// }
  /// ```
  ///
  /// ### Thread safety
  ///
  /// The ``ViewStore`` class is not thread-safe, and all interactions with it (and the store it was
  /// derived from) must happen on the same thread. Further, for SwiftUI applications, all
  /// interactions must happen on the _main_ thread. See the documentation of the ``Store`` class for
  /// more information as to why this decision was made.
@dynamicMemberLookup
public final class ViewStore<State, Action> {
  private let _send: (Action) -> Void
  @MutableProperty fileprivate var _state: State
  private var viewDisposable: Disposable?
  private let (lifetime, token) = Lifetime.make()
  
    /// Initializes a view store from a store.
    ///
    /// - Parameters:
    ///   - store: A store.
    ///   - isDuplicate: A function to determine when two `State` values are equal. When values are
    ///     equal, repeat view computations are removed.
  public init(
    _ store: Store<State, Action>,
    removeDuplicates isDuplicate: @escaping (State, State) -> Bool
  ) {
    self._send = { store.send($0) }
    self._state = store.state
    self.viewDisposable = store.$state.producer
      .skipRepeats(isDuplicate)
      .startWithValues { [weak self] in
        guard let self = self else { return }
        self._state = $0
      }
  }
  
    /// A publisher that emits when state changes.
    ///
    /// This publisher supports dynamic member lookup so that you can pluck out a specific field in
    /// the state:
    ///
    /// ```swift
    /// viewStore.publisher.alert
    ///   .sink { ... }
    /// ```
    ///
    /// When the emission happens the ``ViewStore``'s state has been updated, and so the following
    /// precondition will pass:
    ///
    /// ```swift
    /// viewStore.publisher
    ///   .sink { precondition($0 == viewStore.state) }
    /// ```
    ///
    /// This means you can either use the value passed to the closure or you can reach into
    /// `viewStore.state` directly.
    ///
    /// - Note: Due to a bug in Combine (or feature?), the order you `.sink` on a publisher has no
    ///   bearing on the order the `.sink` closures are called. This means the work performed inside
    ///   `viewStore.publisher.sink` closures should be completely independent of each other.
    ///   Later closures cannot assume that earlier ones have already run.
  public var publisher: StorePublisher<State> {
    StorePublisher(viewStore: self)
  }
  
    /// The current state.
  public var state: State {
    self._state
  }
  
    /// Returns the resulting value of a given key path.
  public subscript<LocalState>(dynamicMember keyPath: KeyPath<State, LocalState>) -> LocalState {
    self.state[keyPath: keyPath]
  }
  
    /// makeBindingTarget
    /// binding view to viewstore
    /// ```swiftt
    /// disposables += viewStore.action <~ buttonLogout.reactive.controlEvents(.touchUpInside).map {_ in ViewAction.logout}
    /// ```
  public func makeBindingTarget<U>(_ action: @escaping (ViewStore, U) -> Void) -> BindingTarget<U> {
    return BindingTarget(on: UIScheduler(), lifetime: lifetime) { [weak self] value in
      if let self = self {
        action(self, value)
      }
    }
  }
    
    /// binding action
    /// binding view to viewstore
    /// ```swiftt
    /// disposables += viewStore.action <~ buttonLogout.reactive.controlEvents(.touchUpInside).map {_ in ViewAction.logout}
    /// ```
  public var action: BindingTarget<Action> {
    makeBindingTarget {
      $0.send($1)
    }
  }
  
    /// Sends an action to the store.
    ///
    /// ``ViewStore`` is not thread safe and you should only send actions to it from the main thread.
    /// If you are wanting to send actions on background threads due to the fact that the reducer
    /// is performing computationally expensive work, then a better way to handle this is to wrap
    /// that work in an ``Effect`` that is performed on a background thread so that the result can
    /// be fed back into the store.
    ///
    /// - Parameter action: An action.
  public func send(_ action: Action) {
    self._send(action)
  }
 
  deinit {
    viewDisposable?.dispose()
  }
}

extension ViewStore where State: Equatable {
  public convenience init(_ store: Store<State, Action>) {
    self.init(store, removeDuplicates: ==)
  }
}

extension ViewStore where State == Void {
  public convenience init(_ store: Store<Void, Action>) {
    self.init(store, removeDuplicates: ==)
  }
}

  /// A publisher of store state.
@dynamicMemberLookup
public struct StorePublisher<State>: SignalProducerConvertible {
  public let upstream: Effect<State, Never>
  public let viewStore: Any
  
    /// The `SignalProducer` representation of `self`.
  public var producer: Effect<State, Never> {
    upstream
  }
  
  fileprivate init<Action>(viewStore: ViewStore<State, Action>) {
    self.viewStore = viewStore
    self.upstream = Property<State>(initial: viewStore.state, then: viewStore.$_state).producer
  }
  
  private init(upstream: Effect<State, Never>,viewStore: Any) {
    self.upstream = upstream
    self.viewStore = viewStore
  }
  
    /// Returns the resulting publisher of a given key path.
  public subscript<LocalState>(dynamicMember keyPath: KeyPath<State, LocalState>) -> StorePublisher<LocalState> where LocalState: Equatable {
    .init(upstream: self.upstream.map(keyPath).skipRepeats(), viewStore: self.viewStore)
  }
}

private struct HashableWrapper<Value>: Hashable {
  let rawValue: Value
  static func == (lhs: Self, rhs: Self) -> Bool { false }
  func hash(into hasher: inout Hasher) {}
}

extension Store {
    /// swith a store to ViewStore
    /// - Returns: ViewStore
  public func asViewStore(removeDuplicates isDuplicate: @escaping (State, State) -> Bool) -> ViewStore<State, Action> {
    ViewStore(self, removeDuplicates: isDuplicate)
  }
  
}

extension Store where State: Equatable {
    /// swith a store to ViewStore
    /// - Returns: ViewStore
  public func asViewStore() -> ViewStore<State, Action> {
    ViewStore(self, removeDuplicates: ==)
  }
}

