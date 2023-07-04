This project combines the ideas from

https://github.com/purcell/postgresql-migrations/tree/master
and
https://gitlab.com/depesz/Versioning/-/tree/master

we want to write our migrations purely in sql and also track dependencies between migrations and have the option of defining rollbacks

to install do something like (depending on where your postgres db is running):

psql postgresql://postgres:postgres@localhost:54322/postgres -f install.sql

psql postgresql://postgres:postgres@localhost:54322/postgres -f example.sql



Some potential future features (via gpt4)

Automatic Dependency Resolution: Enhance the migration system to automatically apply required migrations if they haven't been applied yet, and in the correct order based on dependencies. The same can be done for rollbacks: automatically rollback dependent migrations before rolling back the one they depend on.

Version Numbering for Migrations: Use a version numbering system for migrations (like a timestamp or an incremental number). This can help keep track of the order of migrations and help prevent conflicts when multiple developers are working on the same database.

Rollback All: A functionality that can roll back all migrations to the initial state of the database, in the correct order, respecting the dependencies.
