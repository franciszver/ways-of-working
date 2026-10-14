---
name: clean-code
description: Guides writing and reviewing code for readability and maintainability,
  using clean-code heuristics inspired by Robert C. Martin. Covers names, functions,
  comments, formatting, data and object boundaries, error handling, tests, system
  construction, and code smells. These are heuristics, not fixed rules. Use when writing
  new code, reviewing a diff for readability, or judging whether code is easy to change.
  For a behavior-preserving restructure use refactor. For deleting dead code and clutter
  use declutter.
---

# Clean Code

Clean code is code that the next reader understands fast and changes safely. This skill is a set of heuristics, not a rulebook. Each heuristic is a prompt to look at the code and judge. When a heuristic makes the code harder to read, drop it.

There is no fixed function length, no fixed argument limit, and no required pattern. A long function that reads top to bottom can beat five tiny ones that force the reader to jump around. An abstraction earns its place only when it makes the code easier to read.

## 1. Names

- Pick names that reveal intent. A reader should not need the body to learn what a name means.
- Make names searchable. A magic number or a one-letter name in wide scope is hard to find and hard to change. Use a named constant.
- Use one word per concept. Do not mix `fetch`, `get`, and `retrieve` for the same idea.
- Keep the length of a name in step with the size of its scope. `i` is fine in a three-line loop.
- Avoid encodings, abbreviations only you know, and names that differ by one letter.

## 2. Functions

- A function does one thing at one level of abstraction. If you can describe it only with "and", it may do two things.
- Keep control flow clear. Use guard clauses to cut deep nesting. Prefer the plain path over the clever one.
- Make side effects visible. A function named `check` should not also write to disk. Put the effect in the name or move it out.
- Separate commands from queries. A function should either change state or return information, not both.
- Keep the argument list short because each argument adds a thing to hold in mind. Group related arguments into one value when they travel together. Do not use a boolean flag that switches behavior. Write two functions.
- Do not repeat yourself when the repeats must change together. Leave the repeat alone when the two spots only look alike today.

## 3. Comments

- Let the code say what it does. Comment on why.
- Good comments state intent, a constraint, a tradeoff, a warning, or a link to the reason for an odd choice.
- A comment that restates the code is noise. A comment that has drifted from the code is a bug.
- When you want to write a comment to explain a confusing block, first try a better name or a smaller function.
- Delete commented-out code. Version control keeps it.

## 4. Formatting and local style

- Follow the style of the file and the project. Consistency beats your own taste.
- Keep related code close together. Put a caller above the thing it calls when the language allows.
- Use blank lines to separate ideas. Use a formatter and a linter so style is not a review topic.

## 5. Data, objects, and boundaries

- Hide representation. Expose behavior or a clear interface, not every field.
- Know the tradeoff. Objects make it easy to add new kinds. Plain data structures make it easy to add new operations. Choose on purpose.
- Do not reach through a chain of objects to get to a value you need. Ask the nearest one.
- Use plain transfer records at the edge of the system. Keep them free of business logic.
- Validate input at the boundary. Inside the boundary, trust the types.
- Wrap third-party code behind a small interface you own. Then a change in the library touches one place.

## 6. Error handling

- Fail loudly and early. Never swallow an error to keep going.
- Keep context. Say what was being done, with which input, and why it failed. Wrap an error and keep the original cause.
- Use the error model of the language. Do not mix return codes and exceptions in one layer.
- Do not return a null or sentinel value when the caller cannot tell it from real data. Return an explicit result, an empty collection, or an error.
- Keep the happy path readable. Do not bury it under error checks.

## 7. Tests and testability

- Tests are code and need the same care. A test should read as a short statement of one behavior.
- Fast, independent, repeatable tests are the net that lets you clean code at all.
- Make code easy to test. Pass dependencies in (dependency injection) instead of building them inside. Then a test can supply a fake.
- Keep object construction apart from use. Build the graph in one place, near the entry point, and let the rest of the code ask for what it needs.
- Prefer polymorphism to a long switch repeated in many places. One switch, in one place, is often fine.
- Keep cross-cutting concerns such as logging, retries, and auth out of the core logic when the language and framework give you a clean way to do it.

## 8. Smells to notice

A smell is a hint to look closer, not proof of a defect.

- **Harmful duplication:** the same rule in several places, so a change must hit all of them.
- **Rigidity:** a small change forces edits in many files.
- **Fragility:** a change in one place breaks an unrelated place.
- **Needless complexity:** structure for a future that has not come.
- **Opacity:** code that only its author can follow.
- **Dead code and stale comments.**
- **A function that knows too much about another one's internals.**

## 9. How to apply

- Writing new code: apply these as you go, and leave the code a little cleaner than you found it in the area you touch.
- Reviewing: name each issue with its heuristic and a concrete suggestion. Mark taste as taste. Do not demand a rewrite for a style preference.
- Cleaning existing code: do not mix it with a behavior change. For a behavior-preserving restructure, use `refactor`. For removing dead code, duplication, and clutter from a diff, use `declutter`.
- Stay in scope. Do not clean code the change does not touch.

## Report

```
Scope: <files or diff reviewed>
Findings: <heuristic, location, concrete suggestion; ordered by value>
Taste: <style points marked as optional>
Handoff: <refactor or declutter work that should happen separately>
```

## Anti-patterns

- Treating a heuristic as a hard rule, such as splitting every function under five lines.
- Adding an abstraction, interface, or pattern that makes the code harder to read.
- Renaming or restyling code outside the change, so the diff hides the real edit.
- Changing behavior inside a readability cleanup.
- Writing a comment to excuse code that a better name would fix.
- Removing duplication that only looks alike and is not tied together.
