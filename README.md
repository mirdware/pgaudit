pgAudit
=======
Sistema base de auditoria para tablas postgreSQL. [Marco referencial](http://www.juanluramirez.com/auditoria-bases-datos/).

Migración
---
Pasar se un sistema de multiples tabla a una centralizada implica un trabajo de migración.

1. Eliminar todas las funciones y triggers de las tablas auditadas.
2. Ejecutar **pgaudit.sql** en la base de datos.
3. Si es necesario ejecutar **bind.sql** y/o **split.sql**
4. Pasar los datos de cada una de las tablas a la tabla log con el siguiente comando.
```sql
<?php
INSERT INTO pgaudit.log(table_name, register_date, user_db, session_id, command, old, new)
SELECT 'schema.table', register_date, user_db, log_id, command, row_to_json(old), row_to_json(new)
FROM pgaudit.schema$table
```
5. Ejecutar `pgaudit.follow(schema, table)` nuevamente sobre las tablas a auditar.
6. Eliminar las tablas de auditoria.

Instalación
-----------
Se debe ejecutar el script **pgaudit.sql** dentro de la base de datos a auditar, este proceso generara el esquema pgaudit así como todas las tablas, funciones y triggers para su funcionamiento.

Configuración
-------------
Con solo ejecutar el archivo pgaudit.sql se crea toda la estructura que da soporte al sistema de auditoria, pero no funcionara hasta que se configuren las acciones a auditar; para esto se creo el archivo **config.sql** en él se encuentran los inserts necesarios para alimentar la tabla config del esquema pgaudit.

| key | value | state |
|-----|-------|-------|
| I | INSERT | 1 |
| U | UPDATE | 1 |
| D | DELETE | 1 |

Si el sistema es ejecutado sin una configuración establecida no ingresara datos a las tablas auditadas, de igual manera es posible desactivar la auditoria de un comando cambiando el estado a 0 o eliminado el registro.

Uso
---
Para seguir una tabla se hace uso de la función `pgaudit.follow(schema, table)` o `pgaudit.follow(table)`, en este último caso se fijara la tabla al esquema público de la base de datos. El sistema de auditoria ya no crea tabla por tabla auditada, cualquier log se registra en la tabla *log* eliminando el uso de tablas con forma *pgaudit.schema$table*.

| Campo | Descripción |
|-------|-------------|
| id | Identificador único de la tabla |
| table_name | Nombre de la tabla sobre la cual se realizo la operación  en formato *schema.name* |
| register_date | Fecha enn la que ocurrio el evento |
| user_db | Usuario de la base de datos que modifico el registro |
| session_id | Identificador del acceso de usuario al sistema |
| command | Operación realizada sobre el registro según la configuración del sistema (INSERT, UPDATE, DELETE) |
| old | Registro anterior a la modificación realizada, si la modificación fue de tipo *INSERT* este registro se encuentra vacío |
| new | Registro posterior a la modificación realizada, si la modificación fue de tipo *DELETE* este registro se encuentra vacío |

Al realizar una operación DML sobre una tabla auditada el sistema registra automáticamente en la tabla de auditoria los campos: *id*, *table_name*, *register_date*, *user_db*, *command*, *old* y *new*.

Las operaciones soportadas por pgAudit son: INSERT, UPDATE y DELETE, cada una de estas operaciones crea un registro en la tabla de auditoria siempre y cuando se encuentre activa desde la configuración.

Para deja de seguir una tabla en especifico se debe ejecutar la función `pgaudit.unfollow(schema, table)` o `pgaudit.unfollow(table)`.

Tracking
----
Si se desea realizar auditoria directa sobre la aplicación se debe hacer uso del campo *session_id*, este campo debe enlazarse a la tabla que mantiene la información de ingreso del usuario al sistema o al mismo usuario que ingreso a la aplicación, el registro de esta información se debe realizar implementando la función `pgaudit.bind(session_id)` **bind.sql** dentro de la aplicación.

```php
<?php
$db = new PDO("pgsql:dbname=$dbname;host=$host", $dbuser, $dbpass);
$db->exec("SELECT pgaudit.trail('{$session}')");
```

Se debe tener especial cuidado de ejecutar correctamente esta función, en ocaciones se puede perder la referencia al log ya que la conexión se cierra y con ella la tabla temporal que mantiene el dato en sesión para ser consumido por el trigger.

Dividiendo el log
----
`pgaudit.split(format)` **split.sql** se creo para dividir el log de auditoria por fechas, al ejecutar la función se creará una nueva tabla con la forma *pgaudit.log_(format)* y se eliminarán de la tabla principal los registros. Si se ejecuta sin un formato establecido `pgaudit.split()` se creara una nueva tabla con la forma *pgaudit.log_YYYY_MM_DD_HH24MISSMS*.

Consultas
----
Un registro se puede recuperar fácilmente desde la tabla de auditoria con tan solo usar los campos *old* y *new*, estos almacenan el registro que tenia la tabla antes y después de realizar la operación DML.

```sql
INSERT INTO public.user
SELECT (old->>'id')::integer, old->>'name', old->>'password'
FROM pgaudit.log
WHERE old->>'nombre' = 'admin' AND command = 'D' AND table_name = 'public.user';
```

El manejo de registros como tipo de dato es tan versátil y poderoso que no solo puede restablecer una tabla del sistema, si no que puede realizar cualquier otro tipo de operación como consultas.

```sql
SELECT new, old
FROM pgaudit.log
WHERE table_name = 'public.user' AND new->>'name' = 'admin';
```