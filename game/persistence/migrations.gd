class_name SaveMigrations
extends RefCounted
## Save format migrations: version n -> n + 1. Never edit a released step;
## add a new one and bump SaveCodec.CURRENT_VERSION.
##
## v1 is the first released format, so the table is empty for now. Each new
## step gets a test in tests/unit/persistence/test_migrations.gd.


static func all() -> Dictionary:
	return {}
