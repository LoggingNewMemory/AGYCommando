# OOP Guidelines (LLM Only)

> **Notice**: This document contains strict operational constraints for LLMs and AI agents only. (Developers must figure things out on their own).

## Strict LLM Rules

- **Encapsulation & Invariants**:
  - Keep internal state private/hidden and protect data integrity inside the owning module or object.
  - Expose only minimal, intentional public methods or APIs. Do not blindly generate public getters and setters for every field.
- **Composition over Inheritance**:
  - Favor composing small, focused components over building deep inheritance hierarchies.
  - Avoid multi-level class inheritance chains; use interfaces, traits, protocols, or component fields instead.
- **Depend on Contracts (Decoupling)**:
  - Program against abstractions (interfaces, traits, protocols, or explicit function signatures) rather than concrete implementations.
  - Keep module boundaries explicit so components can be swapped, mocked, or modified independently without cascading edits.
- **Single Responsibility & Cohesion**:
  - Split code into small, modular, reusable units and files grouped by responsibility, not arbitrary line counts.
  - Avoid monolithic files, God classes, and circular dependencies between modules.
- **Tell, Don't Ask**:
  - Keep behavior coupled with the data it operates on.
  - Delegate operations to the owning object or module instead of extracting its internal state to run external conditional logic.
- **Language-Agnostic & Pragmatic**:
  - Apply these principles idiomatically in any language (e.g., `struct` + `trait` in Rust, interfaces in Go, opaque structs in C, classes/protocols in Python/TypeScript).
  - Do not over-engineer with unnecessary OOP boilerplate (e.g., redundant `Factory`, `Manager`, or `Wrapper` classes) when simple data structures and pure functions are cleaner.