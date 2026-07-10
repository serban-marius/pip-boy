---
name: design-patterns
description: >
  Complete GoF design patterns catalog from Refactoring Guru — intent, structure,
  applicability, and relationships for all 22 patterns.
  Trigger: When user mentions a design pattern by name (singleton, strategy, observer, etc.),
  asks "what pattern should I use", "cual patron uso", or is implementing/refactoring
  with a GoF design pattern. Also when analyzing code structure or proposing architecture.
---

## When to Use

Use this skill when:

- User mentions a specific design pattern (e.g., "implement Strategy", "esto necesita un Observer")
- User describes a problem and asks which pattern fits
- Reviewing code that should use (or misuses) a pattern
- Discussing architecture alternatives
- Refactoring towards patterns
- Any mention of GoF, Gang of Four, or Refactoring Guru

---

## Decision Trees

### By Problem Type

```
Creating objects?
├── Don't know concrete type until runtime? → Factory Method
├── Families of related objects? → Abstract Factory
├── Complex construction with many variants? → Builder
├── Expensive to create, want to clone? → Prototype
└── Exactly one instance globally? → Singleton

Making incompatible interfaces work together?
├── Adapt existing interface to expected one? → Adapter
├── Decouple abstraction from implementation? → Bridge
├── Tree structures with uniform treatment? → Composite
├── Add responsibilities without subclassing? → Decorator
├── Simplify complex subsystem? → Facade
├── Share fine-grained objects efficiently? → Flyweight
└── Control access to another object? → Proxy

Managing object communication?
├── Multiple handlers, one processes request? → Chain of Resp.
├── Encapsulate request as object? → Command
├── Traverse collection without exposing internals? → Iterator
├── Reduce chaos of many-to-many communication? → Mediator
├── Capture/restore object state? → Memento
├── One-to-many dependency notification? → Observer
├── Object changes behavior based on internal state? → State
├── Family of interchangeable algorithms? → Strategy
├── Skeleton with overridable steps? → Template Method
└── Operations on object structure without modification? → Visitor
```

### By Non-Functional Concern

```
Performance?
├── Object creation too expensive? → Prototype, Flyweight
├── Too many similar objects? → Flyweight
└── Lazy initialization? → Proxy (virtual), Singleton

Flexibility / Extensibility?
├── Need to add features without modifying? → Decorator, Visitor
├── Need to swap algorithms at runtime? → Strategy
├── Future behavior changes expected? → State, Strategy
└── Open for extension, closed for modification? → Template Method

Complexity Management?
├── Many interacting objects? → Mediator, Facade
├── Complex conditional logic? → Strategy, State, Command
├── Nested conditionals by type? → Polymorphism via Strategy/State
└── Too many subclasses? → Decorator, Visitor
```

### When NOT to Use a Pattern (anti-pattern warnings)

```
Singleton?
  NO if: you just need a global variable, or it introduces hidden dependencies.
  Use DI instead unless truly one instance (logging, hardware access).

Observer?
  NO if: simple callback suffices, or updates are too frequent (flooding).

Visitor?
  NO if: object structure is stable (no new types). Use pattern matching instead.

Decorator?
  NO if: you can just add the behavior to the base class directly.

Factory Method / Abstract Factory?
  NO if: `new` is sufficient. Don't over-engineer object creation.

Strategy?
  NO if: you only have 2 strategies that never change. Use simple conditionals.

Command?
  NO if: you only need a callback. Use functions/lambdas instead.
```

---

## Pattern Catalog

### Creational Patterns

| Pattern          | Intent                                                          | When to Use                                                     |
| ---------------- | --------------------------------------------------------------- | --------------------------------------------------------------- |
| Factory Method   | Define interface for creating one object, let subclasses decide | Class can't anticipate concrete class of objects it must create |
| Abstract Factory | Create families of related/ dependent objects                   | System must be independent of how its products are created      |
| Builder          | Construct complex objects step by step                          | Same construction process creates different representations     |
| Prototype        | Clone existing objects instead of creating from scratch         | Cost of creating new object is expensive/complex                |
| Singleton        | Ensure a class has exactly one instance                         | Exactly one instance needed with global access point            |

#### Factory Method

- **Problem**: A class needs to create objects but shouldn't depend on concrete classes
- **Solution**: Define a method that returns an object; subclasses override to instantiate different concrete types
- **Participants**: `Creator` (declares factory method), `ConcreteCreator` (overrides), `Product`, `ConcreteProduct`
- **Use when**: A class can't anticipate the class of objects it must create; subclasses should specify which class to instantiate
- **Avoid when**: Simple `new` is enough; pattern adds complexity for no reason
- **Relations**:
  - Often called from **Template Method**
  - **Abstract Factory** is often implemented with Factory Methods
  - Can use **Singleton** for the concrete creator

#### Abstract Factory

- **Problem**: Need to create families of related products without specifying concrete classes
- **Solution**: Define interface for creating each product in the family; concrete factories implement for specific variants
- **Participants**: `AbstractFactory`, `ConcreteFactory`, `AbstractProduct`, `ConcreteProduct`
- **Use when**: System should be independent of how products are created; families of related products must be used together
- **Avoid when**: Adding a new product type means changing all factories (violates OCP)
- **Relations**:
  - Built with **Factory Methods**
  - Can use **Singleton** per concrete factory
  - Uses **Prototype** as alternative approach

#### Builder

- **Problem**: Object construction requires many steps, and different representations are needed
- **Solution**: Separate construction steps from final object representation; director orchestrates steps
- **Participants**: `Builder` (interface), `ConcreteBuilder`, `Director`, `Product`
- **Use when**: Complex construction with multiple representations; construction steps should be independent of assembled parts
- **Avoid when**: Object is simple enough to construct with a single constructor or factory
- **Relations**:
  - **Abstract Factory** creates families, Builder creates one complex object
  - Often combined with **Composite** to build complex tree structures
  - Product of Builder can be a **Composite**

#### Prototype

- **Problem**: Creating a full copy of an object is expensive or complex
- **Solution**: Delegate cloning to the objects themselves via a `clone()` method
- **Participants**: `Prototype` (interface), `ConcretePrototype`
- **Use when**: Classes to instantiate are determined at runtime; avoiding factory hierarchy; copying is cheaper than creating new
- **Avoid when**: Deep cloning is complex (circular references, network connections); shallow copy suffices
- **Relations**:
  - Alternative to **Abstract Factory**
  - Often used with **Composite** and **Decorator** to clone complex structures
  - **Command** copies may use Prototype

#### Singleton

- **Problem**: Ensure a class has only one instance with global access
- **Solution**: Make constructor private, provide static method returning always the same instance
- **Participants**: `Singleton`
- **Use when**: Exactly one instance needed with global access (logging, thread pool, cache, hardware interface)
- **Avoid when**: It's just a global variable in disguise; introduces hidden coupling; makes testing harder (use DI instead)
- **Relations**:
  - **Facade** can be a Singleton
  - **Abstract Factory** and **Builder** often implemented as Singletons
  - **Prototype** registry can be a Singleton

---

### Structural Patterns

| Pattern   | Intent                                                                             | When to Use                                                      |
| --------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Adapter   | Convert interface of a class into another interface clients expect                 | Existing class has wrong interface                               |
| Bridge    | Decouple abstraction from implementation so they vary independently                | Need to avoid permanent binding between abstraction and impl     |
| Composite | Compose objects into tree structures, treat individuals and compositions uniformly | Tree structures where clients treat leaf and container uniformly |
| Decorator | Attach additional responsibilities to an object dynamically                        | Alternative to subclassing for extending behavior                |
| Facade    | Provide unified interface to a set of subsystem interfaces                         | Simplify complex subsystem for most clients                      |
| Flyweight | Share fine-grained objects to support large numbers efficiently                    | Many similar objects, memory is concern                          |
| Proxy     | Provide surrogate or placeholder for another object to control access              | Lazy loading, access control, logging, caching                   |

#### Adapter

- **Problem**: Incompatible interfaces — existing class does what you need but with different method signatures
- **Solution**: Wrapper that translates client interface into the adaptee's interface
- **Participants**: `Target` (client interface), `Adapter`, `Adaptee`
- **Use when**: You need to use an existing class but its interface doesn't match; reusing legacy code
- **Avoid when**: You can refactor the interface (just fix it directly)
- **Relations**:
  - **Bridge** is designed upfront; Adapter retrofits existing code
  - **Decorator** adds behavior without changing interface; Adapter changes interface
  - **Proxy** preserves interface; Adapter changes it

#### Bridge

- **Problem**: Both abstraction and implementation should be extensible independently — permanent binding explosion
- **Solution**: Separate abstraction (interface) from implementation — connect via composition
- **Participants**: `Abstraction`, `RefinedAbstraction`, `Implementor`, `ConcreteImplementor`
- **Use when**: Want to avoid class explosion from combining multiple dimensions; both abstraction and impl should be independently sub-classable
- **Avoid when**: Only one implementation exists and won't change
- **Relations**:
  - **Adapter** retrofits; Bridge is designed upfront
  - **Abstract Factory** can configure which implementation Bridge uses
  - **State**, **Strategy** share same structure but different intent (behavioral vs structural)

#### Composite

- **Problem**: Client must treat individual objects and compositions of objects uniformly
- **Solution**: Define component interface with both leaf and composite behaviors; composite stores children
- **Participants**: `Component`, `Leaf`, `Composite`
- **Use when**: Tree structures; clients should ignore difference between compositions and individuals
- **Avoid when**: Uniformity is not needed — simpler to treat leaf and container separately
- **Relations**:
  - **Decorator** has same structure but adds behavior vs. aggregates children
  - **Iterator** can traverse composites
  - **Visitor** can apply operations across composite structure
  - **Chain of Responsibility** uses composite-like structure

#### Decorator

- **Problem**: Need to add responsibilities to individual objects, not to entire class
- **Solution**: Wrapper that implements same interface as wrapped object and adds behavior
- **Participants**: `Component`, `ConcreteComponent`, `Decorator`, `ConcreteDecorator`
- **Use when**: Adding behavior that should be transparent to clients; many combinable behaviors; behavior should be removable
- **Avoid when**: Simple subclassing suffices; decorator chain ordering matters and is hard to manage
- **Relations**:
  - **Adapter** changes interface; Decorator preserves it
  - **Composite** aggregates; Decorator wraps one
  - **Strategy** changes behavior internally; Decorator adds externally
  - Same structure as **Proxy** but different intent

#### Facade

- **Problem**: Complex subsystem with many classes — clients need simple interface for common tasks
- **Solution**: Provide a higher-level unified interface that delegates to subsystem classes
- **Participants**: `Facade`, `SubsystemClasses`
- **Use when**: Want to simplify complex subsystem; want to layer subsystems (facade as entry point)
- **Avoid when**: All clients need full subsystem access (then facade just adds indirection)
- **Relations**:
  - **Mediator** centralizes communication between colleagues; Facade provides simplified interface
  - Usually a **Singleton**
  - **Abstract Factory** can be used with Facade to create subsystem objects

#### Flyweight

- **Problem**: Too many fine-grained objects consuming memory; many share common intrinsic state
- **Solution**: Split object state into intrinsic (shared) and extrinsic (context-dependent); share intrinsic via factory
- **Participants**: `Flyweight`, `ConcreteFlyweight`, `FlyweightFactory`, `Client`
- **Use when**: Application uses large number of objects; storage cost is high; many objects share extrinsic state
- **Avoid when**: Objects have little shared state — overhead of managing factory isn't worth it
- **Relations**:
  - **Composite** can use Flyweight to share leaf nodes
  - **Factory Method** creates flyweight objects
  - **State** can be implemented as Flyweights

#### Proxy

- **Problem**: Need to control access to an object — lazy loading, logging, caching, access control
- **Solution**: Surrogate with same interface; intercepts calls, adds behavior, delegates to real subject
- **Participants**: `Subject` (interface), `RealSubject`, `Proxy`
- **Use when**:
  - _Virtual_: expensive object loaded on demand
  - _Protection_: control access permissions
  - _Remote_: local representation of remote object
  - _Logging_: audit trail
  - _Caching_: memoization
- **Avoid when**: Real subject is always needed or is already lightweight
- **Relations**:
  - **Decorator** same structure, different intent (control access vs add behavior)
  - **Adapter** changes interface, Proxy preserves it
  - **Facade** simplifies, Proxy keeps same interface

---

### Behavioral Patterns

| Pattern         | Intent                                                                    | When to Use                                                      |
| --------------- | ------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Chain of Resp.  | Pass request along handler chain until one handles it                     | Multiple handlers, don't know which will process request         |
| Command         | Encapsulate request as object with all info needed                        | Parameterize clients, queue/log/undo requests                    |
| Iterator        | Access elements sequentially without exposing underlying representation   | Need uniform traversal of different collections                  |
| Mediator        | Centralize complex communication between objects                          | Many-to-many communication becoming tangled                      |
| Memento         | Capture and restore object internal state without violating encapsulation | Undo/rollback functionality                                      |
| Observer        | One-to-many dependency: when one changes, all dependents notified         | Object changes need to notify unknown number of others           |
| State           | Allow object to alter behavior when internal state changes                | Object behaves differently depending on state, many conditionals |
| Strategy        | Define family of interchangeable algorithms                               | Multiple algorithms for same task, need to swap at runtime       |
| Template Method | Define skeleton of algorithm, defer steps to subclasses                   | Algorithm invariant parts vary, subclasses fill in steps         |
| Visitor         | Separate algorithms from object structure on which they operate           | Many distinct operations on stable object structure              |

#### Chain of Responsibility

- **Problem**: Request needs to be processed by one of several handlers; sender doesn't know which
- **Solution**: Chain handlers; each decides to process or pass to next
- **Participants**: `Handler`, `ConcreteHandler`, `Client`
- **Use when**: More than one handler can process request; handler unknown in advance; want to dynamically change handler chain
- **Avoid when**: Every request always handled by first handler (just call it directly)
- **Relations**:
  - **Composite** often used to build handler chains
  - **Command** can be sent along a chain
  - **Mediator** replaces chain for centralized control

#### Command

- **Problem**: Need to parameterize objects with operations; queue, log, or undo operations
- **Solution**: Encapsulate request as object with all context needed to perform it
- **Participants**: `Command`, `ConcreteCommand`, `Receiver`, `Invoker`, `Client`
- **Use when**: Parameterizing actions; queuing/scheduling operations; supporting undo/redo; transactional behavior
- **Avoid when**: Simple callback or lambda suffices (just pass a function)
- **Relations**:
  - **Memento** preserves state for undoable commands
  - **Composite** can implement macro commands (command tree)
  - **Prototype** can be used to copy commands for queuing
  - **Observer** can notify when command completes

#### Iterator

- **Problem**: Need to traverse a collection without exposing its internal structure
- **Solution**: Provide an object that tracks traversal position and returns elements sequentially
- **Participants**: `Iterator`, `ConcreteIterator`, `Aggregate`, `ConcreteAggregate`
- **Use when**: Access to collection contents without exposing representation; multiple traversals; uniform traversal across different collections
- **Avoid when**: Simple for-loop suffices; collection is always array/list
- **Relations**:
  - **Composite** iterators traverse tree structures
  - **Factory Method** creates iterators
  - **Memento** can be used to save iterator state (checkpoint traversal)

#### Mediator

- **Problem**: Many objects communicate in complex web of many-to-many relationships
- **Solution**: Centralize communication in a mediator object; colleagues talk only to mediator
- **Participants**: `Mediator`, `ConcreteMediator`, `Colleague`
- **Use when**: Objects communicate in complex ways hard to reuse; want to centralize control logic
- **Avoid when**: Simple one-to-one or broadcast suffices; mediator becomes god object
- **Relations**:
  - **Facade** simplifies subsystem interface; Mediator centralizes communication
  - **Observer** can implement mediator communication mechanism
  - **Command** can encapsulate requests within mediator

#### Memento

- **Problem**: Need to save/restore object state without breaking encapsulation (private fields)
- **Solution**: Memento object stores snapshot; originator creates/restores; caretaker manages history
- **Participants**: `Originator`, `Memento`, `Caretaker`
- **Use when**: Undo/rollback; checkpoint; snapshot for crash recovery
- **Avoid when**: State can be reconstructed easily; serialization already handles this
- **Relations**:
  - **Command** often uses Memento for undo support
  - **Iterator** can use Memento to save traversal state
  - **Prototype** can serve as alternative for simple state snapshots

#### Observer

- **Problem**: Object changes should notify an unknown number of dependents automatically
- **Solution**: Subject maintains list of observers; on state change, notifies all
- **Participants**: `Subject`, `Observer`, `ConcreteSubject`, `ConcreteObserver`
- **Use when**: Change in one object requires updating others; number of dependents unknown/dynamic; loose coupling needed
- **Avoid when**: Simple callback suffices; update frequency causes performance issues; observers shouldn't know about each other's side effects
- **Relations**:
  - **Mediator** can use Observer to implement event distribution
  - **Singleton** subject can be a Singleton
  - Often combined with **Memento** for snapshot-based notifications

#### State

- **Problem**: Object behavior changes based on internal state; large conditional statements
- **Solution**: Encapsulate each state as class; delegate behavior to current state object
- **Participants**: `Context`, `State`, `ConcreteState`
- **Use when**: Object behavior depends on state and must change at runtime; state-specific conditionals dominate code
- **Avoid when**: Few states with simple transitions; state rarely changes
- **Relations**:
  - **Strategy** has same structure but different intent: State changes behavior based on internal state (automatic), Strategy based on external configuration (client chooses)
  - **Flyweight** can share state objects
  - **Singleton** concrete states are often singletons
  - **Command** can trigger state transitions

#### Strategy

- **Problem**: Multiple algorithms for same task; need to swap at runtime
- **Solution**: Define family of algorithms, encapsulate each, make them interchangeable
- **Participants**: `Context`, `Strategy`, `ConcreteStrategy`
- **Use when**: Many related classes differ only in behavior; multiple variants of an algorithm; algorithm uses data client shouldn't know about
- **Avoid when**: Only 2 strategies that never change; algorithm is simple
- **Relations**:
  - **State** same structure, different intent (see State notes above)
  - **Decorator** changes object skin; Strategy changes guts
  - **Template Method** uses inheritance; Strategy uses composition
  - **Flyweight** can share strategy objects
  - **Command** turns request into object; Strategy turns algorithm into object

#### Template Method

- **Problem**: Algorithm skeleton with invariant structure, but steps vary
- **Solution**: Define algorithm steps as methods, some abstract/hook; subclasses override steps
- **Participants**: `AbstractClass`, `ConcreteClass`
- **Use when**: Invariant parts of algorithm defined once; subclasses implement varying parts; avoid code duplication
- **Avoid when**: All steps vary (use Strategy instead); algorithm is trivial
- **Relations**:
  - **Strategy** uses composition, Template Method uses inheritance
  - **Factory Method** is often called from Template Method
  - **Command** can be combined with Template Method for command processing pipeline

#### Visitor

- **Problem**: Need many distinct operations across a stable object structure without modifying classes
- **Solution**: Separate operations into visitor objects; elements "accept" visitors; visitor has method per element type
- **Participants**: `Visitor`, `ConcreteVisitor`, `Element`, `ConcreteElement`, `ObjectStructure`
- **Use when**: Object structure is stable (few new types), but operations frequently added; many unrelated operations across classes
- **Avoid when**: Object structure changes often (every new type needs visitor update); language has pattern matching/union types
- **Relations**:
  - **Composite** is often the structure visited
  - **Iterator** can traverse the structure for the visitor
  - **Command** can be combined — visitor collects commands to execute
  - **Double Dispatch** is the mechanism behind it

---

## Pattern Relationships

### Patterns That Often Work Together

| Patterns                                  | Why                                                               |
| ----------------------------------------- | ----------------------------------------------------------------- |
| **Composite** + **Visitor**               | Visitor traverses and operates on tree structures                 |
| **Composite** + **Iterator**              | Iterator walks composite tree                                     |
| **Command** + **Memento**                 | Memento saves state for Command undo                              |
| **Chain of Resp.** + **Composite**        | Handler chains often use composite structure                      |
| **Observer** + **Mediator**               | Mediator uses Observer to notify colleagues                       |
| **Factory Method** + **Template Method**  | Template uses Factory Method to create objects                    |
| **Strategy** + **Flyweight**              | Share strategy instances across contexts                          |
| **State** + **Flyweight**                 | Share state objects across contexts                               |
| **Abstract Factory** + **Singleton**      | Each concrete factory is a Singleton                              |
| **Abstract Factory** + **Factory Method** | Factory implemented via Factory Methods                           |
| **Abstract Factory** + **Prototype**      | Prototype as alternative creation approach                        |
| **Facade** + **Singleton**                | Facade is often a Singleton                                       |
| **Decorator** + **Composite**             | Both use recursive composition; composite + decorator is powerful |
| **Builder** + **Composite**               | Builder constructs complex composite trees                        |

### Patterns That Are Alternatives

| Patterns                                   | When to Choose                                                     |
| ------------------------------------------ | ------------------------------------------------------------------ |
| **Strategy** vs **Template Method**        | Composition (Strategy) vs Inheritance (Template) — prefer Strategy |
| **Strategy** vs **State**                  | External config (Strategy) vs Internal transitions (State)         |
| **Decorator** vs **Proxy**                 | Add behavior (Decorator) vs Control access (Proxy)                 |
| **Adapter** vs **Bridge**                  | Retrofit (Adapter) vs Design upfront (Bridge)                      |
| **Factory Method** vs **Abstract Factory** | One product (Factory) vs Product families (Abstract Factory)       |
| **Observer** vs **Mediator**               | Broadcast (Observer) vs Centralized (Mediator)                     |
| **Command** vs **Strategy**                | Encapsulate request (Command) vs Encapsulate algorithm (Strategy)  |
| **Prototype** vs **Factory Method**        | Cloning (Prototype) vs Subclassing (Factory)                       |
| **Facade** vs **Mediator**                 | Simplify subsystem (Facade) vs Centralize communication (Mediator) |

### Pattern Categories by Intent vs Implementation

| Pattern         | Intent Category | Structure       | Key Mechanism                 |
| --------------- | --------------- | --------------- | ----------------------------- |
| Adapter         | Structural      | Wrapper         | Interface translation         |
| Bridge          | Structural      | Two hierarchies | Composition over inheritance  |
| Decorator       | Structural      | Wrapper         | Recursive composition         |
| Proxy           | Structural      | Wrapper         | Surrogate                     |
| Facade          | Structural      | Mediator-like   | Subsystem simplification      |
| State           | Behavioral      | Strategy-like   | Automatic delegation by state |
| Strategy        | Behavioral      | State-like      | Client-configured delegation  |
| Template Method | Behavioral      | Inheritance     | Hook methods                  |
| Chain of Resp.  | Behavioral      | List            | Sequential delegation         |

---

## Code Example Structure

When implementing a pattern, follow this structure:

### Creational

```
Factory Method     → interface Product + interface Creator + concrete classes
Abstract Factory   → interface Factory + interface Product per family + concrete factories
Builder            → interface Builder (steps) + Director (orchestrates) + concrete builders
Prototype          → interface Cloneable + clone() method + registry (optional)
Singleton          → private constructor + static getInstance() + locking (if concurrent)
```

### Structural

```
Adapter            → Target interface + Adapter wrapping Adaptee (class vs object adapter)
Bridge             → Abstraction holding Implementor reference; both independently extensible
Composite          → Component interface (operations + add/remove) + Leaf + Composite
Decorator          → Component interface + ConcreteComponent + Decorator wrapping Component
Facade             → Facade class delegating to subsystem classes
Flyweight          → FlyweightFactory pool + intrinsic/extrinsic state split
Proxy              → Subject interface + RealSubject + Proxy (lazy/protection/remote/virtual)
```

### Behavioral

```
Chain of Resp.     → Handler interface with setNext() + handle() + concrete handlers
Command            → Command interface execute() + ConcreteCommand + Invoker + Receiver
Iterator           → Iterator interface (next/hasNext) + ConcreteIterator + Aggregate
Mediator           → Mediator interface + ConcreteMediator + Colleague interface
Memento            → Memento (immutable snapshot) + Originator (create/restore) + Caretaker
Observer           → Subject (attach/detach/notify) + Observer (update) + concrete classes
State              → Context (delegates to current State) + State interface + ConcreteState
Strategy           → Context (holds Strategy reference) + Strategy interface + ConcreteStrategy
Template Method    → AbstractClass (template method + primitive/hook operations) + ConcreteClass
Visitor            → Visitor (visit per element type) + Element (accept) + ObjectStructure
```

---

## Common Refactoring to Patterns

| Smell / Problem                            | Pattern to Apply                                                  |
| ------------------------------------------ | ----------------------------------------------------------------- |
| Switch on type                             | Replace Conditional with Polymorphism → **Strategy** or **State** |
| Massive constructor                        | **Builder**                                                       |
| Many subclasses just to vary behavior      | **Strategy** or **Decorator**                                     |
| Complex tree traversal                     | **Composite** + **Visitor** or **Iterator**                       |
| Tight coupling, many-to-many communication | **Mediator** or **Observer**                                      |
| Hard to add new operations                 | **Visitor**                                                       |
| Hardcoded class names everywhere           | **Factory Method** or **Abstract Factory**                        |
| God class doing everything                 | **Facade** or **Mediator** to split responsibilities              |
| Long method with algorithms                | **Template Method** or **Strategy**                               |
| Duplicated object creation code            | **Factory Method**                                                |

---

## Resources

- **Full Catalog**: https://refactoring.guru/design-patterns/catalog
- **Pattern by Language**: https://refactoring.guru/design-patterns/examples (C#, Go, Java, PHP, Python, Ruby, Rust, Swift, TypeScript)
- **Classification**: https://refactoring.guru/design-patterns/classification
- **Criticism & When NOT to use**: https://refactoring.guru/design-patterns/criticism
