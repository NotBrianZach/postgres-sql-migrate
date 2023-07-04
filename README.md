This project combines the ideas from

https://github.com/purcell/postgresql-migrations/tree/master

and

https://gitlab.com/depesz/Versioning/-/tree/master

we want to write migrations purely in sql, track dependencies between migrations and optionally define rollbacks

* Install

do something like (depending on where your postgres db is running):

psql postgresql://postgres:postgres@localhost:54322/postgres -f install.sql

* Run

psql postgresql://postgres:postgres@localhost:54322/postgres -f example.sql


* Motivation

previously i had used sqitch to do sql migration, however after I saw depesz sql only library called versioning i think why not store migrations in db, git is unnecessary/bad/inflexible additional component, but depesz required a lot of command line shenanigans/manual execution of files,

a big emacs developer. steve purcell, had his own simpler sql only sql migrations library but it didn't track dependencies so I added a couple columns and some more tables/procedures to do rollbacks as well (which maybe works, also only for postgresql)

and supabase has it's own postgresql migration scheme but it doesn't support dependencies tracking except via numerical file prefixes or partial rollback either it just does everything all at once, which when your are still working on schema and loading/unloading test data into db is perhaps unnecessary annoyance, especially when you are just working on a view or stored procedure and don't need to touch the underlying data at all.

* Some potential future features (via gpt4)

Version Numbering for Migrations: Use a version numbering system for migrations (like a timestamp or an incremental number). This can help keep track of the order of migrations and help prevent conflicts when multiple developers are working on the same database.

Rollback All: A functionality that can roll back all migrations to the initial state of the database, in the correct order, respecting the dependencies.
(personally I start by defining a schema so I can just rollback those, or in the case of public view, just grep for them, then rollback as necessary)
