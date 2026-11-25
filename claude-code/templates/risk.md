# Risk rubric

The factory planner reads this file when it rates a job. List what is `high` risk
in this project: things that are hard to undo or easy to get subtly wrong.
High-risk PRs are never merged by the factory; you merge them.

Always high, in every project: stored data formats and migrations, deleting or
overwriting the user's data, security.

## High in this project

- <e.g. billing, the public API, anything that writes the user's files>

## Notes for low and medium

- <optional: areas that look risky but are not, or the other way round>
