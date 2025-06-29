PGDMP                      }            3dcity-base-db    16.9    16.9 N              0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false                       0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false                       0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false                       1262    31042    3dcity-base-db    DATABASE     �   CREATE DATABASE "3dcity-base-db" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'English_Indonesia.1252';
     DROP DATABASE "3dcity-base-db";
                postgres    false                       0    0    3dcity-base-db    DATABASE PROPERTIES     ^   ALTER DATABASE "3dcity-base-db" SET search_path TO 'citydb', 'citydb_pkg', '$user', 'public';
                     postgres    false            	            2615    32750    citydb    SCHEMA        CREATE SCHEMA citydb;
    DROP SCHEMA citydb;
                postgres    false            
            2615    35202 
   citydb_pkg    SCHEMA        CREATE SCHEMA citydb_pkg;
    DROP SCHEMA citydb_pkg;
                postgres    false                        3079    31043    postgis 	   EXTENSION     ;   CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;
    DROP EXTENSION postgis;
                   false                       0    0    EXTENSION postgis    COMMENT     ^   COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';
                        false    2                        3079    32123    postgis_raster 	   EXTENSION     B   CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;
    DROP EXTENSION postgis_raster;
                   false    2                       0    0    EXTENSION postgis_raster    COMMENT     M   COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';
                        false    3                        3079    32680    postgis_sfcgal 	   EXTENSION     B   CREATE EXTENSION IF NOT EXISTS postgis_sfcgal WITH SCHEMA public;
    DROP EXTENSION postgis_sfcgal;
                   false    2                       0    0    EXTENSION postgis_sfcgal    COMMENT     C   COMMENT ON EXTENSION postgis_sfcgal IS 'PostGIS SFCGAL functions';
                        false    4            u
           1247    35205 	   index_obj    TYPE     �   CREATE TYPE citydb_pkg.index_obj AS (
	index_name text,
	table_name text,
	attribute_name text,
	type numeric(1,0),
	srid integer,
	is_3d numeric(1,0)
);
     DROP TYPE citydb_pkg.index_obj;
    
   citydb_pkg          postgres    false    10                       1255    35058    box2envelope(public.box3d)    FUNCTION     '  CREATE FUNCTION citydb.box2envelope(box public.box3d) RETURNS public.geometry
    LANGUAGE plpgsql STABLE STRICT
    AS $$
DECLARE
  envelope GEOMETRY;
  db_srid INTEGER;
BEGIN
  -- get reference system of input geometry
  IF ST_SRID(box) = 0 THEN
    SELECT srid INTO db_srid FROM citydb.database_srs;
  ELSE
    db_srid := ST_SRID(box);
  END IF;

  SELECT ST_SetSRID(ST_MakePolygon(ST_MakeLine(
    ARRAY[
      ST_MakePoint(ST_XMin(box), ST_YMin(box), ST_ZMin(box)),
      ST_MakePoint(ST_XMax(box), ST_YMin(box), ST_ZMin(box)),
      ST_MakePoint(ST_XMax(box), ST_YMax(box), ST_ZMax(box)),
      ST_MakePoint(ST_XMin(box), ST_YMax(box), ST_ZMax(box)),
      ST_MakePoint(ST_XMin(box), ST_YMin(box), ST_ZMin(box))
    ]
  )), db_srid) INTO envelope;

  RETURN envelope;
END;
$$;
 5   DROP FUNCTION citydb.box2envelope(box public.box3d);
       citydb          postgres    false    2    2    2    2    2    2    2    2    2    2    2    9            c           1255    35105    cleanup_appearances(integer)    FUNCTION     �  CREATE FUNCTION citydb.cleanup_appearances(only_global integer DEFAULT 1) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
  app_id bigint;
BEGIN
  PERFORM citydb.del_surface_data(array_agg(s.id))
    FROM citydb.surface_data s 
    LEFT OUTER JOIN citydb.textureparam t ON s.id = t.surface_data_id
    WHERE t.surface_data_id IS NULL;

    IF only_global=1 THEN
      FOR app_id IN
        SELECT a.id FROM citydb.appearance a
          LEFT OUTER JOIN citydb.appear_to_surface_data asd ON a.id=asd.appearance_id
            WHERE a.cityobject_id IS NULL AND asd.appearance_id IS NULL
      LOOP
        DELETE FROM citydb.appearance WHERE id = app_id RETURNING id INTO deleted_id;
        RETURN NEXT deleted_id;
      END LOOP;
    ELSE
      FOR app_id IN
        SELECT a.id FROM citydb.appearance a
          LEFT OUTER JOIN citydb.appear_to_surface_data asd ON a.id=asd.appearance_id
            WHERE asd.appearance_id IS NULL
      LOOP
        DELETE FROM citydb.appearance WHERE id = app_id RETURNING id INTO deleted_id;
        RETURN NEXT deleted_id;
      END LOOP;
    END IF;

  RETURN;
END;
$$;
 ?   DROP FUNCTION citydb.cleanup_appearances(only_global integer);
       citydb          postgres    false    9            ?           1255    35106    cleanup_schema()    FUNCTION     �  CREATE FUNCTION citydb.cleanup_schema() RETURNS SETOF void
    LANGUAGE plpgsql
    AS $$
-- Function for cleaning up data schema
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT table_name FROM information_schema.tables where table_schema = 'citydb'
    AND table_name <> 'database_srs'
    AND table_name <> 'objectclass'
    AND table_name <> 'index_table'
    AND table_name <> 'ade'
    AND table_name <> 'schema'
    AND table_name <> 'schema_to_objectclass'
    AND table_name <> 'schema_referencing'
    AND table_name <> 'aggregation_info'
    AND table_name NOT LIKE 'tmp_%'
  LOOP
    EXECUTE format('TRUNCATE TABLE citydb.%I CASCADE', rec.table_name);
  END LOOP;

  FOR rec IN 
    SELECT sequence_name FROM information_schema.sequences where sequence_schema = 'citydb'
    AND sequence_name <> 'ade_seq'
    AND sequence_name <> 'schema_seq'
  LOOP
    EXECUTE format('ALTER SEQUENCE citydb.%I RESTART', rec.sequence_name);	
  END LOOP;
END;
$$;
 '   DROP FUNCTION citydb.cleanup_schema();
       citydb          postgres    false    9            ]           1255    35107    cleanup_table(text)    FUNCTION     %	  CREATE FUNCTION citydb.cleanup_table(tab_name text) RETURNS SETOF bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
  rec RECORD;
  rec_id BIGINT;
  where_clause TEXT;
  query_ddl TEXT;
  counter BIGINT;
  table_alias TEXT;
  table_name_with_schemaprefix TEXT;
  del_func_name TEXT;
  schema_name TEXT;
  deleted_id BIGINT;
BEGIN
  schema_name = 'citydb';
  IF md5(schema_name) <> '373663016e8a76eedd0e1ac37f392d2a' THEN
    table_name_with_schemaprefix = schema_name || '.' || tab_name;
  ELSE
    table_name_with_schemaprefix = tab_name;
  END IF;

  counter = 0;
  del_func_name = 'del_' || tab_name;
  query_ddl = 'SELECT id FROM ' || schema_name || '.' || tab_name || ' WHERE id IN ('
    || 'SELECT a.id FROM ' || schema_name || '.' || tab_name || ' a';

  FOR rec IN
    SELECT
      c.confrelid::regclass::text AS root_table_name,
      c.conrelid::regclass::text AS fk_table_name,
      a.attname::text AS fk_column_name
    FROM
      pg_constraint c
    JOIN
      pg_attribute a
      ON a.attrelid = c.conrelid
      AND a.attnum = ANY (c.conkey)
    WHERE
      upper(c.confrelid::regclass::text) = upper(table_name_with_schemaprefix)
      AND c.conrelid <> c.confrelid
      AND c.contype = 'f'
    ORDER BY
      fk_table_name,
      fk_column_name
  LOOP
    counter = counter + 1;
    table_alias = 'n' || counter;
    IF counter = 1 THEN
      where_clause = ' WHERE ' || table_alias || '.' || rec.fk_column_name || ' IS NULL';
    ELSE
      where_clause = where_clause || ' AND ' || table_alias || '.' || rec.fk_column_name || ' IS NULL';
    END IF;

    IF md5(schema_name) <> '373663016e8a76eedd0e1ac37f392d2a' THEN
      query_ddl = query_ddl || ' LEFT JOIN ' || rec.fk_table_name || ' ' || table_alias || ' ON '
        || table_alias || '.' || rec.fk_column_name || ' = a.id';
    ELSE
      query_ddl = query_ddl || ' LEFT JOIN ' || schema_name || '.' || rec.fk_table_name || ' ' || table_alias || ' ON '
        || table_alias || '.' || rec.fk_column_name || ' = a.id';
    END IF;
  END LOOP;

  query_ddl = query_ddl || where_clause || ')';

  FOR rec_id IN EXECUTE query_ddl LOOP
    EXECUTE 'SELECT ' || schema_name || '.' || del_func_name || '(' || rec_id || ')' INTO deleted_id;
    RETURN NEXT deleted_id;
  END LOOP;

  RETURN;
END;
$$;
 3   DROP FUNCTION citydb.cleanup_table(tab_name text);
       citydb          postgres    false    9            0           1255    35109    del_address(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_address(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_address(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 .   DROP FUNCTION citydb.del_address(pid bigint);
       citydb          postgres    false    9            �           1255    35108    del_address(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_address(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.addresss
  WITH delete_objects AS (
    DELETE FROM
      citydb.address t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 <   DROP FUNCTION citydb.del_address(bigint[], caller integer);
       citydb          postgres    false    9                       1255    35111    del_appearance(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_appearance(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_appearance(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 1   DROP FUNCTION citydb.del_appearance(pid bigint);
       citydb          postgres    false    9            �           1255    35110 !   del_appearance(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_appearance(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_data_ids bigint[] := '{}';
BEGIN
  -- delete references to surface_datas
  WITH del_surface_data_refs AS (
    DELETE FROM
      citydb.appear_to_surface_data t
    USING
      unnest($1) a(a_id)
    WHERE
      t.appearance_id = a.a_id
    RETURNING
      t.surface_data_id
  )
  SELECT
    array_agg(surface_data_id)
  INTO
    surface_data_ids
  FROM
    del_surface_data_refs;

  -- delete citydb.surface_data(s)
  IF -1 = ALL(surface_data_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_data(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_data_ids) AS a_id) a
    LEFT JOIN
      citydb.appear_to_surface_data n1
      ON n1.surface_data_id  = a.a_id
    WHERE n1.surface_data_id IS NULL;
  END IF;

  -- delete citydb.appearances
  WITH delete_objects AS (
    DELETE FROM
      citydb.appearance t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ?   DROP FUNCTION citydb.del_appearance(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35113    del_breakline_relief(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_breakline_relief(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_breakline_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_breakline_relief(pid bigint);
       citydb          postgres    false    9                       1255    35112 '   del_breakline_relief(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_breakline_relief(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.breakline_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.breakline_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_breakline_relief(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35115    del_bridge(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 -   DROP FUNCTION citydb.del_bridge(pid bigint);
       citydb          postgres    false    9            �           1255    35114    del_bridge(bigint[], integer)    FUNCTION     I  CREATE FUNCTION citydb.del_bridge(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  address_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_bridge(array_agg(t.id))
  FROM
    citydb.bridge t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_bridge(array_agg(t.id))
  FROM
    citydb.bridge t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete references to addresss
  WITH del_address_refs AS (
    DELETE FROM
      citydb.address_to_bridge t
    USING
      unnest($1) a(a_id)
    WHERE
      t.bridge_id = a.a_id
    RETURNING
      t.address_id
  )
  SELECT
    array_agg(address_id)
  INTO
    address_ids
  FROM
    del_address_refs;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  --delete bridge_constr_elements
  PERFORM
    citydb.del_bridge_constr_element(array_agg(t.id))
  FROM
    citydb.bridge_constr_element t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_installations
  PERFORM
    citydb.del_bridge_installation(array_agg(t.id))
  FROM
    citydb.bridge_installation t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_rooms
  PERFORM
    citydb.del_bridge_room(array_agg(t.id))
  FROM
    citydb.bridge_room t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_id = a.a_id;

  -- delete citydb.bridges
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ;   DROP FUNCTION citydb.del_bridge(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35117 !   del_bridge_constr_element(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_constr_element(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_constr_element(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 <   DROP FUNCTION citydb.del_bridge_constr_element(pid bigint);
       citydb          postgres    false    9            <           1255    35116 ,   del_bridge_constr_element(bigint[], integer)    FUNCTION     
  CREATE FUNCTION citydb.del_bridge_constr_element(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.bridge_constr_elements
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_constr_element t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 J   DROP FUNCTION citydb.del_bridge_constr_element(bigint[], caller integer);
       citydb          postgres    false    9                       1255    35119    del_bridge_furniture(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_furniture(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_bridge_furniture(pid bigint);
       citydb          postgres    false    9                       1255    35118 '   del_bridge_furniture(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_bridge_furniture(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.bridge_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_bridge_furniture(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35121    del_bridge_installation(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_installation(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 :   DROP FUNCTION citydb.del_bridge_installation(pid bigint);
       citydb          postgres    false    9            �           1255    35120 *   del_bridge_installation(bigint[], integer)    FUNCTION     m  CREATE FUNCTION citydb.del_bridge_installation(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_installation_id = a.a_id;

  -- delete citydb.bridge_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 H   DROP FUNCTION citydb.del_bridge_installation(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35123    del_bridge_opening(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_opening(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 5   DROP FUNCTION citydb.del_bridge_opening(pid bigint);
       citydb          postgres    false    9            y           1255    35122 %   del_bridge_opening(bigint[], integer)    FUNCTION     %  CREATE FUNCTION citydb.del_bridge_opening(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
  address_ids bigint[] := '{}';
BEGIN
  -- delete citydb.bridge_openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      address_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id),
    array_agg(address_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids,
    address_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 C   DROP FUNCTION citydb.del_bridge_opening(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35125    del_bridge_room(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_room(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_room(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 2   DROP FUNCTION citydb.del_bridge_room(pid bigint);
       citydb          postgres    false    9            �           1255    35124 "   del_bridge_room(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_bridge_room(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete bridge_furnitures
  PERFORM
    citydb.del_bridge_furniture(array_agg(t.id))
  FROM
    citydb.bridge_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  --delete bridge_installations
  PERFORM
    citydb.del_bridge_installation(array_agg(t.id))
  FROM
    citydb.bridge_installation t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  --delete bridge_thematic_surfaces
  PERFORM
    citydb.del_bridge_thematic_surface(array_agg(t.id))
  FROM
    citydb.bridge_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.bridge_room_id = a.a_id;

  -- delete citydb.bridge_rooms
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_room t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 @   DROP FUNCTION citydb.del_bridge_room(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35127 #   del_bridge_thematic_surface(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_bridge_thematic_surface(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_bridge_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 >   DROP FUNCTION citydb.del_bridge_thematic_surface(pid bigint);
       citydb          postgres    false    9            f           1255    35126 .   del_bridge_thematic_surface(bigint[], integer)    FUNCTION     <  CREATE FUNCTION citydb.del_bridge_thematic_surface(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  bridge_opening_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete references to bridge_openings
  WITH del_bridge_opening_refs AS (
    DELETE FROM
      citydb.bridge_open_to_them_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.bridge_thematic_surface_id = a.a_id
    RETURNING
      t.bridge_opening_id
  )
  SELECT
    array_agg(bridge_opening_id)
  INTO
    bridge_opening_ids
  FROM
    del_bridge_opening_refs;

  -- delete citydb.bridge_opening(s)
  IF -1 = ALL(bridge_opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_bridge_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(bridge_opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.bridge_thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.bridge_thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 L   DROP FUNCTION citydb.del_bridge_thematic_surface(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35129    del_building(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_building(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_building(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 /   DROP FUNCTION citydb.del_building(pid bigint);
       citydb          postgres    false    9            �           1255    35128    del_building(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_building(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  address_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_building(array_agg(t.id))
  FROM
    citydb.building t,
    unnest($1) a(a_id)
  WHERE
    t.building_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_building(array_agg(t.id))
  FROM
    citydb.building t,
    unnest($1) a(a_id)
  WHERE
    t.building_root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete references to addresss
  WITH del_address_refs AS (
    DELETE FROM
      citydb.address_to_building t
    USING
      unnest($1) a(a_id)
    WHERE
      t.building_id = a.a_id
    RETURNING
      t.address_id
  )
  SELECT
    array_agg(address_id)
  INTO
    address_ids
  FROM
    del_address_refs;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  --delete building_installations
  PERFORM
    citydb.del_building_installation(array_agg(t.id))
  FROM
    citydb.building_installation t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  --delete rooms
  PERFORM
    citydb.del_room(array_agg(t.id))
  FROM
    citydb.room t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.building_id = a.a_id;

  -- delete citydb.buildings
  WITH delete_objects AS (
    DELETE FROM
      citydb.building t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_footprint_id,
      lod0_roofprint_id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_footprint_id) ||
    array_agg(lod0_roofprint_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 =   DROP FUNCTION citydb.del_building(bigint[], caller integer);
       citydb          postgres    false    9                       1255    35131    del_building_furniture(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_building_furniture(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_building_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 9   DROP FUNCTION citydb.del_building_furniture(pid bigint);
       citydb          postgres    false    9            E           1255    35130 )   del_building_furniture(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_building_furniture(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.building_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.building_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 G   DROP FUNCTION citydb.del_building_furniture(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35133 !   del_building_installation(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_building_installation(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_building_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 <   DROP FUNCTION citydb.del_building_installation(pid bigint);
       citydb          postgres    false    9            �           1255    35132 ,   del_building_installation(bigint[], integer)    FUNCTION     `  CREATE FUNCTION citydb.del_building_installation(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.building_installation_id = a.a_id;

  -- delete citydb.building_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.building_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 J   DROP FUNCTION citydb.del_building_installation(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35135    del_city_furniture(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_city_furniture(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_city_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 5   DROP FUNCTION citydb.del_city_furniture(pid bigint);
       citydb          postgres    false    9            /           1255    35134 %   del_city_furniture(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_city_furniture(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.city_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.city_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 C   DROP FUNCTION citydb.del_city_furniture(bigint[], caller integer);
       citydb          postgres    false    9            @           1255    35137    del_citymodel(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_citymodel(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_citymodel(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 0   DROP FUNCTION citydb.del_citymodel(pid bigint);
       citydb          postgres    false    9            �           1255    35136     del_citymodel(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_citymodel(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  cityobject_ids bigint[] := '{}';
BEGIN
  --delete appearances
  PERFORM
    citydb.del_appearance(array_agg(t.id))
  FROM
    citydb.appearance t,
    unnest($1) a(a_id)
  WHERE
    t.citymodel_id = a.a_id;

  -- delete references to cityobjects
  WITH del_cityobject_refs AS (
    DELETE FROM
      citydb.cityobject_member t
    USING
      unnest($1) a(a_id)
    WHERE
      t.citymodel_id = a.a_id
    RETURNING
      t.cityobject_id
  )
  SELECT
    array_agg(cityobject_id)
  INTO
    cityobject_ids
  FROM
    del_cityobject_refs;

  -- delete citydb.cityobject(s)
  IF -1 = ALL(cityobject_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_cityobject(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(cityobject_ids) AS a_id) a
    LEFT JOIN
      citydb.cityobject_member n1
      ON n1.cityobject_id  = a.a_id
    LEFT JOIN
      citydb.group_to_cityobject n2
      ON n2.cityobject_id  = a.a_id
    WHERE n1.cityobject_id IS NULL
      AND n2.cityobject_id IS NULL;
  END IF;

  -- delete citydb.citymodels
  WITH delete_objects AS (
    DELETE FROM
      citydb.citymodel t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 >   DROP FUNCTION citydb.del_citymodel(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35140    del_cityobject(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_cityobject(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_cityobject(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 1   DROP FUNCTION citydb.del_cityobject(pid bigint);
       citydb          postgres    false    9            P           1255    35138 !   del_cityobject(bigint[], integer)    FUNCTION     )?  CREATE FUNCTION citydb.del_cityobject(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  --delete appearances
  PERFORM
    citydb.del_appearance(array_agg(t.id))
  FROM
    citydb.appearance t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  --delete cityobject_genericattribs
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  --delete external_references
  PERFORM
    citydb.del_external_reference(array_agg(t.id))
  FROM
    citydb.external_reference t,
    unnest($1) a(a_id)
  WHERE
    t.cityobject_id = a.a_id;

  IF $2 <> 2 THEN
    FOR rec IN
      SELECT
        co.id, co.objectclass_id
      FROM
        citydb.cityobject co, unnest($1) a(a_id)
      WHERE
        co.id = a.a_id
    LOOP
      object_id := rec.id::bigint;
      objectclass_id := rec.objectclass_id::integer;
      CASE
        -- delete land_use
        WHEN objectclass_id = 4 THEN
          dummy_id := citydb.del_land_use(array_agg(object_id), 1);
        -- delete generic_cityobject
        WHEN objectclass_id = 5 THEN
          dummy_id := citydb.del_generic_cityobject(array_agg(object_id), 1);
        -- delete solitary_vegetat_object
        WHEN objectclass_id = 7 THEN
          dummy_id := citydb.del_solitary_vegetat_object(array_agg(object_id), 1);
        -- delete plant_cover
        WHEN objectclass_id = 8 THEN
          dummy_id := citydb.del_plant_cover(array_agg(object_id), 1);
        -- delete waterbody
        WHEN objectclass_id = 9 THEN
          dummy_id := citydb.del_waterbody(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 10 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 11 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 12 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete waterboundary_surface
        WHEN objectclass_id = 13 THEN
          dummy_id := citydb.del_waterboundary_surface(array_agg(object_id), 1);
        -- delete relief_feature
        WHEN objectclass_id = 14 THEN
          dummy_id := citydb.del_relief_feature(array_agg(object_id), 1);
        -- delete relief_component
        WHEN objectclass_id = 15 THEN
          dummy_id := citydb.del_relief_component(array_agg(object_id), 1);
        -- delete tin_relief
        WHEN objectclass_id = 16 THEN
          dummy_id := citydb.del_tin_relief(array_agg(object_id), 0);
        -- delete masspoint_relief
        WHEN objectclass_id = 17 THEN
          dummy_id := citydb.del_masspoint_relief(array_agg(object_id), 0);
        -- delete breakline_relief
        WHEN objectclass_id = 18 THEN
          dummy_id := citydb.del_breakline_relief(array_agg(object_id), 0);
        -- delete raster_relief
        WHEN objectclass_id = 19 THEN
          dummy_id := citydb.del_raster_relief(array_agg(object_id), 0);
        -- delete city_furniture
        WHEN objectclass_id = 21 THEN
          dummy_id := citydb.del_city_furniture(array_agg(object_id), 1);
        -- delete cityobjectgroup
        WHEN objectclass_id = 23 THEN
          dummy_id := citydb.del_cityobjectgroup(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 24 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 25 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building
        WHEN objectclass_id = 26 THEN
          dummy_id := citydb.del_building(array_agg(object_id), 1);
        -- delete building_installation
        WHEN objectclass_id = 27 THEN
          dummy_id := citydb.del_building_installation(array_agg(object_id), 1);
        -- delete building_installation
        WHEN objectclass_id = 28 THEN
          dummy_id := citydb.del_building_installation(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 29 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 30 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 31 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 32 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 33 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 34 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 35 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 36 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 37 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 38 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete opening
        WHEN objectclass_id = 39 THEN
          dummy_id := citydb.del_opening(array_agg(object_id), 1);
        -- delete building_furniture
        WHEN objectclass_id = 40 THEN
          dummy_id := citydb.del_building_furniture(array_agg(object_id), 1);
        -- delete room
        WHEN objectclass_id = 41 THEN
          dummy_id := citydb.del_room(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 42 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 43 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 44 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 45 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete transportation_complex
        WHEN objectclass_id = 46 THEN
          dummy_id := citydb.del_transportation_complex(array_agg(object_id), 1);
        -- delete traffic_area
        WHEN objectclass_id = 47 THEN
          dummy_id := citydb.del_traffic_area(array_agg(object_id), 1);
        -- delete traffic_area
        WHEN objectclass_id = 48 THEN
          dummy_id := citydb.del_traffic_area(array_agg(object_id), 1);
        -- delete appearance
        WHEN objectclass_id = 50 THEN
          dummy_id := citydb.del_appearance(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 51 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 52 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 53 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 54 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete surface_data
        WHEN objectclass_id = 55 THEN
          dummy_id := citydb.del_surface_data(array_agg(object_id), 0);
        -- delete citymodel
        WHEN objectclass_id = 57 THEN
          dummy_id := citydb.del_citymodel(array_agg(object_id), 0);
        -- delete address
        WHEN objectclass_id = 58 THEN
          dummy_id := citydb.del_address(array_agg(object_id), 0);
        -- delete implicit_geometry
        WHEN objectclass_id = 59 THEN
          dummy_id := citydb.del_implicit_geometry(array_agg(object_id), 0);
        -- delete thematic_surface
        WHEN objectclass_id = 60 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete thematic_surface
        WHEN objectclass_id = 61 THEN
          dummy_id := citydb.del_thematic_surface(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 62 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 63 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge
        WHEN objectclass_id = 64 THEN
          dummy_id := citydb.del_bridge(array_agg(object_id), 1);
        -- delete bridge_installation
        WHEN objectclass_id = 65 THEN
          dummy_id := citydb.del_bridge_installation(array_agg(object_id), 1);
        -- delete bridge_installation
        WHEN objectclass_id = 66 THEN
          dummy_id := citydb.del_bridge_installation(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 67 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 68 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 69 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 70 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 71 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 72 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 73 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 74 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 75 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_thematic_surface
        WHEN objectclass_id = 76 THEN
          dummy_id := citydb.del_bridge_thematic_surface(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 77 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 78 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_opening
        WHEN objectclass_id = 79 THEN
          dummy_id := citydb.del_bridge_opening(array_agg(object_id), 1);
        -- delete bridge_furniture
        WHEN objectclass_id = 80 THEN
          dummy_id := citydb.del_bridge_furniture(array_agg(object_id), 1);
        -- delete bridge_room
        WHEN objectclass_id = 81 THEN
          dummy_id := citydb.del_bridge_room(array_agg(object_id), 1);
        -- delete bridge_constr_element
        WHEN objectclass_id = 82 THEN
          dummy_id := citydb.del_bridge_constr_element(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 83 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 84 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel
        WHEN objectclass_id = 85 THEN
          dummy_id := citydb.del_tunnel(array_agg(object_id), 1);
        -- delete tunnel_installation
        WHEN objectclass_id = 86 THEN
          dummy_id := citydb.del_tunnel_installation(array_agg(object_id), 1);
        -- delete tunnel_installation
        WHEN objectclass_id = 87 THEN
          dummy_id := citydb.del_tunnel_installation(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 88 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 89 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 90 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 91 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 92 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 93 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 94 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 95 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 96 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_thematic_surface
        WHEN objectclass_id = 97 THEN
          dummy_id := citydb.del_tunnel_thematic_surface(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 98 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 99 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_opening
        WHEN objectclass_id = 100 THEN
          dummy_id := citydb.del_tunnel_opening(array_agg(object_id), 1);
        -- delete tunnel_furniture
        WHEN objectclass_id = 101 THEN
          dummy_id := citydb.del_tunnel_furniture(array_agg(object_id), 1);
        -- delete tunnel_hollow_space
        WHEN objectclass_id = 102 THEN
          dummy_id := citydb.del_tunnel_hollow_space(array_agg(object_id), 1);
        ELSE
          dummy_id := NULL;
      END CASE;

      IF dummy_id = object_id THEN
        deleted_child_ids := array_append(deleted_child_ids, dummy_id);
      END IF;
    END LOOP;
  END IF;

  -- delete citydb.cityobjects
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ?   DROP FUNCTION citydb.del_cityobject(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35142 $   del_cityobject_genericattrib(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_cityobject_genericattrib(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_cityobject_genericattrib(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 ?   DROP FUNCTION citydb.del_cityobject_genericattrib(pid bigint);
       citydb          postgres    false    9            _           1255    35141 /   del_cityobject_genericattrib(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_cityobject_genericattrib(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.parent_genattrib_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_cityobject_genericattrib(array_agg(t.id))
  FROM
    citydb.cityobject_genericattrib t,
    unnest($1) a(a_id)
  WHERE
    t.root_genattrib_id = a.a_id
    AND t.id <> a.a_id;

  -- delete citydb.cityobject_genericattribs
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobject_genericattrib t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      surface_geometry_id
  )
  SELECT
    array_agg(id),
    array_agg(surface_geometry_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 M   DROP FUNCTION citydb.del_cityobject_genericattrib(bigint[], caller integer);
       citydb          postgres    false    9            #           1255    35144    del_cityobjectgroup(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_cityobjectgroup(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_cityobjectgroup(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 6   DROP FUNCTION citydb.del_cityobjectgroup(pid bigint);
       citydb          postgres    false    9            �           1255    35143 &   del_cityobjectgroup(bigint[], integer)    FUNCTION     :  CREATE FUNCTION citydb.del_cityobjectgroup(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  cityobject_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete references to cityobjects
  WITH del_cityobject_refs AS (
    DELETE FROM
      citydb.group_to_cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.cityobjectgroup_id = a.a_id
    RETURNING
      t.cityobject_id
  )
  SELECT
    array_agg(cityobject_id)
  INTO
    cityobject_ids
  FROM
    del_cityobject_refs;

  -- delete citydb.cityobject(s)
  IF -1 = ALL(cityobject_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_cityobject(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(cityobject_ids) AS a_id) a
    LEFT JOIN
      citydb.cityobject_member n1
      ON n1.cityobject_id  = a.a_id
    LEFT JOIN
      citydb.group_to_cityobject n2
      ON n2.cityobject_id  = a.a_id
    WHERE n1.cityobject_id IS NULL
      AND n2.cityobject_id IS NULL;
  END IF;

  -- delete citydb.cityobjectgroups
  WITH delete_objects AS (
    DELETE FROM
      citydb.cityobjectgroup t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      brep_id
  )
  SELECT
    array_agg(id),
    array_agg(brep_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 D   DROP FUNCTION citydb.del_cityobjectgroup(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35145 )   del_cityobjects_by_lineage(text, integer)    FUNCTION     �  CREATE FUNCTION citydb.del_cityobjects_by_lineage(lineage_value text, objectclass_id integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
-- Function for deleting cityobjects by lineage value
DECLARE
  deleted_ids bigint[] := '{}';
BEGIN
  IF $2 = 0 THEN
    SELECT array_agg(c.id) FROM
      citydb.cityobject c
    INTO
      deleted_ids
    WHERE
      c.lineage = $1;
  ELSE
    SELECT array_agg(c.id) FROM
      citydb.cityobject c
    INTO
      deleted_ids
    WHERE
      c.lineage = $1 AND c.objectclass_id = $2;
  END IF;

  IF -1 = ALL(deleted_ids) IS NOT NULL THEN
    PERFORM citydb.del_cityobject(deleted_ids);
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ]   DROP FUNCTION citydb.del_cityobjects_by_lineage(lineage_value text, objectclass_id integer);
       citydb          postgres    false    9            �           1255    35147    del_external_reference(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_external_reference(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_external_reference(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 9   DROP FUNCTION citydb.del_external_reference(pid bigint);
       citydb          postgres    false    9                       1255    35146 )   del_external_reference(bigint[], integer)    FUNCTION       CREATE FUNCTION citydb.del_external_reference(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.external_references
  WITH delete_objects AS (
    DELETE FROM
      citydb.external_reference t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 G   DROP FUNCTION citydb.del_external_reference(bigint[], caller integer);
       citydb          postgres    false    9            V           1255    35149    del_generic_cityobject(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_generic_cityobject(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_generic_cityobject(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 9   DROP FUNCTION citydb.del_generic_cityobject(pid bigint);
       citydb          postgres    false    9            /           1255    35148 )   del_generic_cityobject(bigint[], integer)    FUNCTION     {  CREATE FUNCTION citydb.del_generic_cityobject(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.generic_cityobjects
  WITH delete_objects AS (
    DELETE FROM
      citydb.generic_cityobject t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_implicit_rep_id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod0_brep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_implicit_rep_id) ||
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod0_brep_id) ||
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 G   DROP FUNCTION citydb.del_generic_cityobject(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35151    del_grid_coverage(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_grid_coverage(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_grid_coverage(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 4   DROP FUNCTION citydb.del_grid_coverage(pid bigint);
       citydb          postgres    false    9            �           1255    35150 $   del_grid_coverage(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_grid_coverage(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.grid_coverages
  WITH delete_objects AS (
    DELETE FROM
      citydb.grid_coverage t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 B   DROP FUNCTION citydb.del_grid_coverage(bigint[], caller integer);
       citydb          postgres    false    9            B           1255    35153    del_implicit_geometry(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_implicit_geometry(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_implicit_geometry(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 8   DROP FUNCTION citydb.del_implicit_geometry(pid bigint);
       citydb          postgres    false    9            �           1255    35152 (   del_implicit_geometry(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_implicit_geometry(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.implicit_geometrys
  WITH delete_objects AS (
    DELETE FROM
      citydb.implicit_geometry t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      relative_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(relative_brep_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 F   DROP FUNCTION citydb.del_implicit_geometry(bigint[], caller integer);
       citydb          postgres    false    9            3           1255    35155    del_land_use(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_land_use(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_land_use(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 /   DROP FUNCTION citydb.del_land_use(pid bigint);
       citydb          postgres    false    9            q           1255    35154    del_land_use(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_land_use(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.land_uses
  WITH delete_objects AS (
    DELETE FROM
      citydb.land_use t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_multi_surface_id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_multi_surface_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 =   DROP FUNCTION citydb.del_land_use(bigint[], caller integer);
       citydb          postgres    false    9            	           1255    35157    del_masspoint_relief(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_masspoint_relief(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_masspoint_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_masspoint_relief(pid bigint);
       citydb          postgres    false    9            O           1255    35156 '   del_masspoint_relief(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_masspoint_relief(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.masspoint_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.masspoint_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_masspoint_relief(bigint[], caller integer);
       citydb          postgres    false    9            Q           1255    35159    del_opening(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_opening(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 .   DROP FUNCTION citydb.del_opening(pid bigint);
       citydb          postgres    false    9            �           1255    35158    del_opening(bigint[], integer)    FUNCTION       CREATE FUNCTION citydb.del_opening(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
  address_ids bigint[] := '{}';
BEGIN
  -- delete citydb.openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      address_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id),
    array_agg(address_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids,
    address_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  -- delete citydb.address(s)
  IF -1 = ALL(address_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_address(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(address_ids) AS a_id) a
    LEFT JOIN
      citydb.address_to_bridge n1
      ON n1.address_id  = a.a_id
    LEFT JOIN
      citydb.address_to_building n2
      ON n2.address_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n3
      ON n3.address_id  = a.a_id
    LEFT JOIN
      citydb.opening n4
      ON n4.address_id  = a.a_id
    WHERE n1.address_id IS NULL
      AND n2.address_id IS NULL
      AND n3.address_id IS NULL
      AND n4.address_id IS NULL;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 <   DROP FUNCTION citydb.del_opening(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35161    del_plant_cover(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_plant_cover(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_plant_cover(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 2   DROP FUNCTION citydb.del_plant_cover(pid bigint);
       citydb          postgres    false    9            R           1255    35160 "   del_plant_cover(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_plant_cover(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.plant_covers
  WITH delete_objects AS (
    DELETE FROM
      citydb.plant_cover t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_multi_solid_id,
      lod2_multi_solid_id,
      lod3_multi_solid_id,
      lod4_multi_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_multi_solid_id) ||
    array_agg(lod2_multi_solid_id) ||
    array_agg(lod3_multi_solid_id) ||
    array_agg(lod4_multi_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 @   DROP FUNCTION citydb.del_plant_cover(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35163    del_raster_relief(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_raster_relief(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_raster_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 4   DROP FUNCTION citydb.del_raster_relief(pid bigint);
       citydb          postgres    false    9            �           1255    35162 $   del_raster_relief(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_raster_relief(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  grid_coverage_ids bigint[] := '{}';
BEGIN
  -- delete citydb.raster_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.raster_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      coverage_id
  )
  SELECT
    array_agg(id),
    array_agg(coverage_id)
  INTO
    deleted_ids,
    grid_coverage_ids
  FROM
    delete_objects;

  -- delete citydb.grid_coverage(s)
  IF -1 = ALL(grid_coverage_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_grid_coverage(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(grid_coverage_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 B   DROP FUNCTION citydb.del_raster_relief(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35165    del_relief_component(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_relief_component(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_relief_component(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_relief_component(pid bigint);
       citydb          postgres    false    9            �           1255    35164 '   del_relief_component(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_relief_component(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  IF $2 <> 2 THEN
    FOR rec IN
      SELECT
        co.id, co.objectclass_id
      FROM
        citydb.cityobject co, unnest($1) a(a_id)
      WHERE
        co.id = a.a_id
    LOOP
      object_id := rec.id::bigint;
      objectclass_id := rec.objectclass_id::integer;
      CASE
        -- delete tin_relief
        WHEN objectclass_id = 16 THEN
          dummy_id := citydb.del_tin_relief(array_agg(object_id), 1);
        -- delete masspoint_relief
        WHEN objectclass_id = 17 THEN
          dummy_id := citydb.del_masspoint_relief(array_agg(object_id), 1);
        -- delete breakline_relief
        WHEN objectclass_id = 18 THEN
          dummy_id := citydb.del_breakline_relief(array_agg(object_id), 1);
        -- delete raster_relief
        WHEN objectclass_id = 19 THEN
          dummy_id := citydb.del_raster_relief(array_agg(object_id), 1);
        ELSE
          dummy_id := NULL;
      END CASE;

      IF dummy_id = object_id THEN
        deleted_child_ids := array_append(deleted_child_ids, dummy_id);
      END IF;
    END LOOP;
  END IF;

  -- delete citydb.relief_components
  WITH delete_objects AS (
    DELETE FROM
      citydb.relief_component t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_relief_component(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35167    del_relief_feature(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_relief_feature(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_relief_feature(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 5   DROP FUNCTION citydb.del_relief_feature(pid bigint);
       citydb          postgres    false    9            �           1255    35166 %   del_relief_feature(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_relief_feature(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  relief_component_ids bigint[] := '{}';
BEGIN
  -- delete references to relief_components
  WITH del_relief_component_refs AS (
    DELETE FROM
      citydb.relief_feat_to_rel_comp t
    USING
      unnest($1) a(a_id)
    WHERE
      t.relief_feature_id = a.a_id
    RETURNING
      t.relief_component_id
  )
  SELECT
    array_agg(relief_component_id)
  INTO
    relief_component_ids
  FROM
    del_relief_component_refs;

  -- delete citydb.relief_component(s)
  IF -1 = ALL(relief_component_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_relief_component(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(relief_component_ids) AS a_id) a
    LEFT JOIN
      citydb.relief_feat_to_rel_comp n1
      ON n1.relief_component_id  = a.a_id
    WHERE n1.relief_component_id IS NULL;
  END IF;

  -- delete citydb.relief_features
  WITH delete_objects AS (
    DELETE FROM
      citydb.relief_feature t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 C   DROP FUNCTION citydb.del_relief_feature(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35169    del_room(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_room(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_room(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 +   DROP FUNCTION citydb.del_room(pid bigint);
       citydb          postgres    false    9            �           1255    35168    del_room(bigint[], integer)    FUNCTION     \  CREATE FUNCTION citydb.del_room(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete building_furnitures
  PERFORM
    citydb.del_building_furniture(array_agg(t.id))
  FROM
    citydb.building_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  --delete building_installations
  PERFORM
    citydb.del_building_installation(array_agg(t.id))
  FROM
    citydb.building_installation t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  --delete thematic_surfaces
  PERFORM
    citydb.del_thematic_surface(array_agg(t.id))
  FROM
    citydb.thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.room_id = a.a_id;

  -- delete citydb.rooms
  WITH delete_objects AS (
    DELETE FROM
      citydb.room t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 9   DROP FUNCTION citydb.del_room(bigint[], caller integer);
       citydb          postgres    false    9            p           1255    35171 #   del_solitary_vegetat_object(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_solitary_vegetat_object(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_solitary_vegetat_object(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 >   DROP FUNCTION citydb.del_solitary_vegetat_object(pid bigint);
       citydb          postgres    false    9            g           1255    35170 .   del_solitary_vegetat_object(bigint[], integer)    FUNCTION       CREATE FUNCTION citydb.del_solitary_vegetat_object(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.solitary_vegetat_objects
  WITH delete_objects AS (
    DELETE FROM
      citydb.solitary_vegetat_object t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_implicit_rep_id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod1_brep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_implicit_rep_id) ||
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod1_brep_id) ||
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 L   DROP FUNCTION citydb.del_solitary_vegetat_object(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35173    del_surface_data(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_surface_data(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_surface_data(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 3   DROP FUNCTION citydb.del_surface_data(pid bigint);
       citydb          postgres    false    9            �           1255    35172 #   del_surface_data(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_surface_data(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  tex_image_ids bigint[] := '{}';
BEGIN
  -- delete citydb.surface_datas
  WITH delete_objects AS (
    DELETE FROM
      citydb.surface_data t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      tex_image_id
  )
  SELECT
    array_agg(id),
    array_agg(tex_image_id)
  INTO
    deleted_ids,
    tex_image_ids
  FROM
    delete_objects;

  -- delete citydb.tex_image(s)
  IF -1 = ALL(tex_image_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_tex_image(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(tex_image_ids) AS a_id) a
    LEFT JOIN
      citydb.surface_data n1
      ON n1.tex_image_id  = a.a_id
    WHERE n1.tex_image_id IS NULL;
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 A   DROP FUNCTION citydb.del_surface_data(bigint[], caller integer);
       citydb          postgres    false    9            =           1255    35175    del_surface_geometry(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_surface_geometry(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_surface_geometry(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_surface_geometry(pid bigint);
       citydb          postgres    false    9            B           1255    35174 '   del_surface_geometry(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_surface_geometry(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_surface_geometry(array_agg(t.id))
  FROM
    citydb.surface_geometry t,
    unnest($1) a(a_id)
  WHERE
    t.parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_surface_geometry(array_agg(t.id))
  FROM
    citydb.surface_geometry t,
    unnest($1) a(a_id)
  WHERE
    t.root_id = a.a_id
    AND t.id <> a.a_id;

  -- delete citydb.surface_geometrys
  WITH delete_objects AS (
    DELETE FROM
      citydb.surface_geometry t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_surface_geometry(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35177    del_tex_image(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tex_image(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tex_image(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 0   DROP FUNCTION citydb.del_tex_image(pid bigint);
       citydb          postgres    false    9            �           1255    35176     del_tex_image(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_tex_image(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
BEGIN
  -- delete citydb.tex_images
  WITH delete_objects AS (
    DELETE FROM
      citydb.tex_image t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id
  )
  SELECT
    array_agg(id)
  INTO
    deleted_ids
  FROM
    delete_objects;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 >   DROP FUNCTION citydb.del_tex_image(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35179    del_thematic_surface(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_thematic_surface(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_thematic_surface(pid bigint);
       citydb          postgres    false    9            �           1255    35178 '   del_thematic_surface(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_thematic_surface(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  opening_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete references to openings
  WITH del_opening_refs AS (
    DELETE FROM
      citydb.opening_to_them_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.thematic_surface_id = a.a_id
    RETURNING
      t.opening_id
  )
  SELECT
    array_agg(opening_id)
  INTO
    opening_ids
  FROM
    del_opening_refs;

  -- delete citydb.opening(s)
  IF -1 = ALL(opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_thematic_surface(bigint[], caller integer);
       citydb          postgres    false    9            V           1255    35181    del_tin_relief(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tin_relief(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tin_relief(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 1   DROP FUNCTION citydb.del_tin_relief(pid bigint);
       citydb          postgres    false    9            �           1255    35180 !   del_tin_relief(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_tin_relief(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.tin_reliefs
  WITH delete_objects AS (
    DELETE FROM
      citydb.tin_relief t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      surface_geometry_id
  )
  SELECT
    array_agg(id),
    array_agg(surface_geometry_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete relief_component
    PERFORM citydb.del_relief_component(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ?   DROP FUNCTION citydb.del_tin_relief(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35183    del_traffic_area(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_traffic_area(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_traffic_area(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 3   DROP FUNCTION citydb.del_traffic_area(pid bigint);
       citydb          postgres    false    9            �           1255    35182 #   del_traffic_area(bigint[], integer)    FUNCTION     y  CREATE FUNCTION citydb.del_traffic_area(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.traffic_areas
  WITH delete_objects AS (
    DELETE FROM
      citydb.traffic_area t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 A   DROP FUNCTION citydb.del_traffic_area(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35185 "   del_transportation_complex(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_transportation_complex(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_transportation_complex(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 =   DROP FUNCTION citydb.del_transportation_complex(pid bigint);
       citydb          postgres    false    9            r           1255    35184 -   del_transportation_complex(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_transportation_complex(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete traffic_areas
  PERFORM
    citydb.del_traffic_area(array_agg(t.id))
  FROM
    citydb.traffic_area t,
    unnest($1) a(a_id)
  WHERE
    t.transportation_complex_id = a.a_id;

  -- delete citydb.transportation_complexs
  WITH delete_objects AS (
    DELETE FROM
      citydb.transportation_complex t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 K   DROP FUNCTION citydb.del_transportation_complex(bigint[], caller integer);
       citydb          postgres    false    9            (           1255    35187    del_tunnel(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 -   DROP FUNCTION citydb.del_tunnel(pid bigint);
       citydb          postgres    false    9                       1255    35186    del_tunnel(bigint[], integer)    FUNCTION     �
  CREATE FUNCTION citydb.del_tunnel(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete referenced parts
  PERFORM
    citydb.del_tunnel(array_agg(t.id))
  FROM
    citydb.tunnel t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_parent_id = a.a_id
    AND t.id <> a.a_id;

  -- delete referenced parts
  PERFORM
    citydb.del_tunnel(array_agg(t.id))
  FROM
    citydb.tunnel t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_root_id = a.a_id
    AND t.id <> a.a_id;

  --delete tunnel_hollow_spaces
  PERFORM
    citydb.del_tunnel_hollow_space(array_agg(t.id))
  FROM
    citydb.tunnel_hollow_space t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  --delete tunnel_installations
  PERFORM
    citydb.del_tunnel_installation(array_agg(t.id))
  FROM
    citydb.tunnel_installation t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_id = a.a_id;

  -- delete citydb.tunnels
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod1_multi_surface_id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 ;   DROP FUNCTION citydb.del_tunnel(bigint[], caller integer);
       citydb          postgres    false    9            h           1255    35189    del_tunnel_furniture(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel_furniture(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel_furniture(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 7   DROP FUNCTION citydb.del_tunnel_furniture(pid bigint);
       citydb          postgres    false    9            �           1255    35188 '   del_tunnel_furniture(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_tunnel_furniture(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.tunnel_furnitures
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_furniture t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_implicit_rep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_implicit_rep_id),
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 E   DROP FUNCTION citydb.del_tunnel_furniture(bigint[], caller integer);
       citydb          postgres    false    9                       1255    35191    del_tunnel_hollow_space(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel_hollow_space(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel_hollow_space(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 :   DROP FUNCTION citydb.del_tunnel_hollow_space(pid bigint);
       citydb          postgres    false    9                       1255    35190 *   del_tunnel_hollow_space(bigint[], integer)    FUNCTION     �  CREATE FUNCTION citydb.del_tunnel_hollow_space(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete tunnel_furnitures
  PERFORM
    citydb.del_tunnel_furniture(array_agg(t.id))
  FROM
    citydb.tunnel_furniture t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  --delete tunnel_installations
  PERFORM
    citydb.del_tunnel_installation(array_agg(t.id))
  FROM
    citydb.tunnel_installation t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_hollow_space_id = a.a_id;

  -- delete citydb.tunnel_hollow_spaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_hollow_space t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod4_multi_surface_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod4_multi_surface_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 H   DROP FUNCTION citydb.del_tunnel_hollow_space(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35193    del_tunnel_installation(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel_installation(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel_installation(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 :   DROP FUNCTION citydb.del_tunnel_installation(pid bigint);
       citydb          postgres    false    9            �           1255    35192 *   del_tunnel_installation(bigint[], integer)    FUNCTION     m  CREATE FUNCTION citydb.del_tunnel_installation(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  --delete tunnel_thematic_surfaces
  PERFORM
    citydb.del_tunnel_thematic_surface(array_agg(t.id))
  FROM
    citydb.tunnel_thematic_surface t,
    unnest($1) a(a_id)
  WHERE
    t.tunnel_installation_id = a.a_id;

  -- delete citydb.tunnel_installations
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_installation t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_implicit_rep_id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod2_brep_id,
      lod3_brep_id,
      lod4_brep_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_implicit_rep_id) ||
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod2_brep_id) ||
    array_agg(lod3_brep_id) ||
    array_agg(lod4_brep_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 H   DROP FUNCTION citydb.del_tunnel_installation(bigint[], caller integer);
       citydb          postgres    false    9            m           1255    35195    del_tunnel_opening(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel_opening(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel_opening(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 5   DROP FUNCTION citydb.del_tunnel_opening(pid bigint);
       citydb          postgres    false    9            X           1255    35194 %   del_tunnel_opening(bigint[], integer)    FUNCTION     %  CREATE FUNCTION citydb.del_tunnel_opening(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  implicit_geometry_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.tunnel_openings
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_opening t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod3_implicit_rep_id,
      lod4_implicit_rep_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod3_implicit_rep_id) ||
    array_agg(lod4_implicit_rep_id),
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    implicit_geometry_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.implicit_geometry(s)
  IF -1 = ALL(implicit_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_implicit_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(implicit_geometry_ids) AS a_id) a
    LEFT JOIN
      citydb.bridge_constr_element n1
      ON n1.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n2
      ON n2.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n3
      ON n3.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_constr_element n4
      ON n4.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_furniture n5
      ON n5.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n6
      ON n6.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n7
      ON n7.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_installation n8
      ON n8.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n9
      ON n9.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.bridge_opening n10
      ON n10.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_furniture n11
      ON n11.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n12
      ON n12.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n13
      ON n13.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.building_installation n14
      ON n14.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n15
      ON n15.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n16
      ON n16.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n17
      ON n17.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.city_furniture n18
      ON n18.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n19
      ON n19.lod0_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n20
      ON n20.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n21
      ON n21.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n22
      ON n22.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.generic_cityobject n23
      ON n23.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n24
      ON n24.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.opening n25
      ON n25.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n26
      ON n26.lod1_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n27
      ON n27.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n28
      ON n28.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.solitary_vegetat_object n29
      ON n29.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_furniture n30
      ON n30.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n31
      ON n31.lod2_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n32
      ON n32.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_installation n33
      ON n33.lod4_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n34
      ON n34.lod3_implicit_rep_id  = a.a_id
    LEFT JOIN
      citydb.tunnel_opening n35
      ON n35.lod4_implicit_rep_id  = a.a_id
    WHERE n1.lod1_implicit_rep_id IS NULL
      AND n2.lod2_implicit_rep_id IS NULL
      AND n3.lod3_implicit_rep_id IS NULL
      AND n4.lod4_implicit_rep_id IS NULL
      AND n5.lod4_implicit_rep_id IS NULL
      AND n6.lod2_implicit_rep_id IS NULL
      AND n7.lod3_implicit_rep_id IS NULL
      AND n8.lod4_implicit_rep_id IS NULL
      AND n9.lod3_implicit_rep_id IS NULL
      AND n10.lod4_implicit_rep_id IS NULL
      AND n11.lod4_implicit_rep_id IS NULL
      AND n12.lod2_implicit_rep_id IS NULL
      AND n13.lod3_implicit_rep_id IS NULL
      AND n14.lod4_implicit_rep_id IS NULL
      AND n15.lod1_implicit_rep_id IS NULL
      AND n16.lod2_implicit_rep_id IS NULL
      AND n17.lod3_implicit_rep_id IS NULL
      AND n18.lod4_implicit_rep_id IS NULL
      AND n19.lod0_implicit_rep_id IS NULL
      AND n20.lod1_implicit_rep_id IS NULL
      AND n21.lod2_implicit_rep_id IS NULL
      AND n22.lod3_implicit_rep_id IS NULL
      AND n23.lod4_implicit_rep_id IS NULL
      AND n24.lod3_implicit_rep_id IS NULL
      AND n25.lod4_implicit_rep_id IS NULL
      AND n26.lod1_implicit_rep_id IS NULL
      AND n27.lod2_implicit_rep_id IS NULL
      AND n28.lod3_implicit_rep_id IS NULL
      AND n29.lod4_implicit_rep_id IS NULL
      AND n30.lod4_implicit_rep_id IS NULL
      AND n31.lod2_implicit_rep_id IS NULL
      AND n32.lod3_implicit_rep_id IS NULL
      AND n33.lod4_implicit_rep_id IS NULL
      AND n34.lod3_implicit_rep_id IS NULL
      AND n35.lod4_implicit_rep_id IS NULL;
  END IF;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 C   DROP FUNCTION citydb.del_tunnel_opening(bigint[], caller integer);
       citydb          postgres    false    9            N           1255    35197 #   del_tunnel_thematic_surface(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_tunnel_thematic_surface(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_tunnel_thematic_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 >   DROP FUNCTION citydb.del_tunnel_thematic_surface(pid bigint);
       citydb          postgres    false    9            ^           1255    35196 .   del_tunnel_thematic_surface(bigint[], integer)    FUNCTION     <  CREATE FUNCTION citydb.del_tunnel_thematic_surface(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  tunnel_opening_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete references to tunnel_openings
  WITH del_tunnel_opening_refs AS (
    DELETE FROM
      citydb.tunnel_open_to_them_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.tunnel_thematic_surface_id = a.a_id
    RETURNING
      t.tunnel_opening_id
  )
  SELECT
    array_agg(tunnel_opening_id)
  INTO
    tunnel_opening_ids
  FROM
    del_tunnel_opening_refs;

  -- delete citydb.tunnel_opening(s)
  IF -1 = ALL(tunnel_opening_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_tunnel_opening(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(tunnel_opening_ids) AS a_id) a;
  END IF;

  -- delete citydb.tunnel_thematic_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.tunnel_thematic_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_multi_surface_id,
      lod3_multi_surface_id,
      lod4_multi_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_multi_surface_id) ||
    array_agg(lod3_multi_surface_id) ||
    array_agg(lod4_multi_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 L   DROP FUNCTION citydb.del_tunnel_thematic_surface(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35199    del_waterbody(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_waterbody(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_waterbody(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 0   DROP FUNCTION citydb.del_waterbody(pid bigint);
       citydb          postgres    false    9            �           1255    35198     del_waterbody(bigint[], integer)    FUNCTION     	  CREATE FUNCTION citydb.del_waterbody(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  waterboundary_surface_ids bigint[] := '{}';
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete references to waterboundary_surfaces
  WITH del_waterboundary_surface_refs AS (
    DELETE FROM
      citydb.waterbod_to_waterbnd_srf t
    USING
      unnest($1) a(a_id)
    WHERE
      t.waterbody_id = a.a_id
    RETURNING
      t.waterboundary_surface_id
  )
  SELECT
    array_agg(waterboundary_surface_id)
  INTO
    waterboundary_surface_ids
  FROM
    del_waterboundary_surface_refs;

  -- delete citydb.waterboundary_surface(s)
  IF -1 = ALL(waterboundary_surface_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_waterboundary_surface(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(waterboundary_surface_ids) AS a_id) a
    LEFT JOIN
      citydb.waterbod_to_waterbnd_srf n1
      ON n1.waterboundary_surface_id  = a.a_id
    WHERE n1.waterboundary_surface_id IS NULL;
  END IF;

  -- delete citydb.waterbodys
  WITH delete_objects AS (
    DELETE FROM
      citydb.waterbody t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod0_multi_surface_id,
      lod1_multi_surface_id,
      lod1_solid_id,
      lod2_solid_id,
      lod3_solid_id,
      lod4_solid_id
  )
  SELECT
    array_agg(id),
    array_agg(lod0_multi_surface_id) ||
    array_agg(lod1_multi_surface_id) ||
    array_agg(lod1_solid_id) ||
    array_agg(lod2_solid_id) ||
    array_agg(lod3_solid_id) ||
    array_agg(lod4_solid_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 >   DROP FUNCTION citydb.del_waterbody(bigint[], caller integer);
       citydb          postgres    false    9                       1255    35201 !   del_waterboundary_surface(bigint)    FUNCTION     �   CREATE FUNCTION citydb.del_waterboundary_surface(pid bigint) RETURNS bigint
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  deleted_id bigint;
BEGIN
  deleted_id := citydb.del_waterboundary_surface(ARRAY[pid]);
  RETURN deleted_id;
END;
$$;
 <   DROP FUNCTION citydb.del_waterboundary_surface(pid bigint);
       citydb          postgres    false    9                       1255    35200 ,   del_waterboundary_surface(bigint[], integer)    FUNCTION     p  CREATE FUNCTION citydb.del_waterboundary_surface(bigint[], caller integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  deleted_ids bigint[] := '{}';
  dummy_id bigint;
  deleted_child_ids bigint[] := '{}';
  object_id bigint;
  objectclass_id integer;
  rec RECORD;
  surface_geometry_ids bigint[] := '{}';
BEGIN
  -- delete citydb.waterboundary_surfaces
  WITH delete_objects AS (
    DELETE FROM
      citydb.waterboundary_surface t
    USING
      unnest($1) a(a_id)
    WHERE
      t.id = a.a_id
    RETURNING
      id,
      lod2_surface_id,
      lod3_surface_id,
      lod4_surface_id
  )
  SELECT
    array_agg(id),
    array_agg(lod2_surface_id) ||
    array_agg(lod3_surface_id) ||
    array_agg(lod4_surface_id)
  INTO
    deleted_ids,
    surface_geometry_ids
  FROM
    delete_objects;

  -- delete citydb.surface_geometry(s)
  IF -1 = ALL(surface_geometry_ids) IS NOT NULL THEN
    PERFORM
      citydb.del_surface_geometry(array_agg(a.a_id))
    FROM
      (SELECT DISTINCT unnest(surface_geometry_ids) AS a_id) a;
  END IF;

  IF $2 <> 1 THEN
    -- delete cityobject
    PERFORM citydb.del_cityobject(deleted_ids, 2);
  END IF;

  IF array_length(deleted_child_ids, 1) > 0 THEN
    deleted_ids := deleted_child_ids;
  END IF;

  RETURN QUERY
    SELECT unnest(deleted_ids);
END;
$_$;
 J   DROP FUNCTION citydb.del_waterboundary_surface(bigint[], caller integer);
       citydb          postgres    false    9            �           1255    35059 %   env_address(bigint, integer, integer)    FUNCTION     N  CREATE FUNCTION citydb.env_address(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- multiPoint
    SELECT multi_point AS geom FROM citydb.address WHERE id = co_id  AND multi_point IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 V   DROP FUNCTION citydb.env_address(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9                       1255    35060 (   env_appearance(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_appearance(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _SurfaceData
    SELECT citydb.env_surface_data(c.id, set_envelope) AS geom FROM citydb.surface_data c, citydb.appear_to_surface_data p2c WHERE c.id = surface_data_id AND p2c.appearance_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 Y   DROP FUNCTION citydb.env_appearance(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            �           1255    35061 .   env_breakline_relief(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_breakline_relief(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- ridgeOrValleyLines
    SELECT ridge_or_valley_lines AS geom FROM citydb.breakline_relief WHERE id = co_id  AND ridge_or_valley_lines IS NOT NULL
      UNION ALL
    -- breaklines
    SELECT break_lines AS geom FROM citydb.breakline_relief WHERE id = co_id  AND break_lines IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_breakline_relief(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            L           1255    35062 $   env_bridge(bigint, integer, integer)    FUNCTION     }  CREATE FUNCTION citydb.env_bridge(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.bridge WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.bridge WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- BridgeConstructionElement
    SELECT citydb.env_bridge_constr_element(id, set_envelope) AS geom FROM citydb.bridge_constr_element WHERE bridge_id = co_id
      UNION ALL
    -- BridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_id = co_id
      UNION ALL
    -- IntBridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_id = co_id
      UNION ALL
    -- BridgeRoom
    SELECT citydb.env_bridge_room(id, set_envelope) AS geom FROM citydb.bridge_room WHERE bridge_id = co_id
      UNION ALL
    -- BridgePart
    SELECT citydb.env_bridge(id, set_envelope) AS geom FROM citydb.bridge WHERE bridge_parent_id = co_id
      UNION ALL
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.address c, citydb.address_to_bridge p2c WHERE c.id = address_id AND p2c.bridge_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 U   DROP FUNCTION citydb.env_bridge(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            Y           1255    35063 3   env_bridge_constr_element(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_bridge_constr_element(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_constr_element t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.bridge_constr_element WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_constr_element WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 d   DROP FUNCTION citydb.env_bridge_constr_element(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            >           1255    35064 .   env_bridge_furniture(bigint, integer, integer)    FUNCTION        CREATE FUNCTION citydb.env_bridge_furniture(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_bridge_furniture(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2                        1255    35065 1   env_bridge_installation(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_bridge_installation(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.bridge_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 b   DROP FUNCTION citydb.env_bridge_installation(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35066 ,   env_bridge_opening(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_bridge_opening(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.bridge_opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.bridge_opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.bridge_opening p, address c WHERE p.id = co_id AND p.address_id = c.id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 ]   DROP FUNCTION citydb.env_bridge_opening(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9                       1255    35067 )   env_bridge_room(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_bridge_room(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_room t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_room t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_bridge_thematic_surface(id, set_envelope) AS geom FROM citydb.bridge_thematic_surface WHERE bridge_room_id = co_id
      UNION ALL
    -- BridgeFurniture
    SELECT citydb.env_bridge_furniture(id, set_envelope) AS geom FROM citydb.bridge_furniture WHERE bridge_room_id = co_id
      UNION ALL
    -- IntBridgeInstallation
    SELECT citydb.env_bridge_installation(id, set_envelope) AS geom FROM citydb.bridge_installation WHERE bridge_room_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 Z   DROP FUNCTION citydb.env_bridge_room(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35068 5   env_bridge_thematic_surface(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_bridge_thematic_surface(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.bridge_thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BridgeOpening
    SELECT citydb.env_bridge_opening(c.id, set_envelope) AS geom FROM citydb.bridge_opening c, citydb.bridge_open_to_them_srf p2c WHERE c.id = bridge_opening_id AND p2c.bridge_thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 f   DROP FUNCTION citydb.env_bridge_thematic_surface(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            #           1255    35069 &   env_building(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_building(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0FootPrint
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod0_footprint_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod0RoofEdge
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod0_roofprint_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.building WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.building WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- BuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE building_id = co_id
      UNION ALL
    -- IntBuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE building_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_id = co_id
      UNION ALL
    -- Room
    SELECT citydb.env_room(id, set_envelope) AS geom FROM citydb.room WHERE building_id = co_id
      UNION ALL
    -- BuildingPart
    SELECT citydb.env_building(id, set_envelope) AS geom FROM citydb.building WHERE building_parent_id = co_id
      UNION ALL
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.address c, citydb.address_to_building p2c WHERE c.id = address_id AND p2c.building_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 W   DROP FUNCTION citydb.env_building(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            V           1255    35070 0   env_building_furniture(bigint, integer, integer)    FUNCTION       CREATE FUNCTION citydb.env_building_furniture(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 a   DROP FUNCTION citydb.env_building_furniture(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            y           1255    35071 3   env_building_installation(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_building_installation(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.building_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.building_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.building_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE building_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 d   DROP FUNCTION citydb.env_building_installation(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            :           1255    35072 ,   env_city_furniture(bigint, integer, integer)    FUNCTION     #  CREATE FUNCTION citydb.env_city_furniture(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.city_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.city_furniture WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.city_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 ]   DROP FUNCTION citydb.env_city_furniture(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            >           1255    35073 '   env_citymodel(bigint, integer, integer)    FUNCTION       CREATE FUNCTION citydb.env_citymodel(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;
 X   DROP FUNCTION citydb.env_citymodel(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35074 (   env_cityobject(bigint, integer, integer)    FUNCTION     G6  CREATE FUNCTION citydb.env_cityobject(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Appearance
    SELECT citydb.env_appearance(id, set_envelope) AS geom FROM citydb.appearance WHERE cityobject_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  IF caller <> 2 THEN
    SELECT objectclass_id INTO class_id FROM citydb.cityobject WHERE id = co_id;
    CASE
      -- land_use
      WHEN class_id = 4 THEN
        dummy_bbox := citydb.env_land_use(co_id, set_envelope, 1);
      -- generic_cityobject
      WHEN class_id = 5 THEN
        dummy_bbox := citydb.env_generic_cityobject(co_id, set_envelope, 1);
      -- solitary_vegetat_object
      WHEN class_id = 7 THEN
        dummy_bbox := citydb.env_solitary_vegetat_object(co_id, set_envelope, 1);
      -- plant_cover
      WHEN class_id = 8 THEN
        dummy_bbox := citydb.env_plant_cover(co_id, set_envelope, 1);
      -- waterbody
      WHEN class_id = 9 THEN
        dummy_bbox := citydb.env_waterbody(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 10 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 11 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 12 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- waterboundary_surface
      WHEN class_id = 13 THEN
        dummy_bbox := citydb.env_waterboundary_surface(co_id, set_envelope, 1);
      -- relief_feature
      WHEN class_id = 14 THEN
        dummy_bbox := citydb.env_relief_feature(co_id, set_envelope, 1);
      -- relief_component
      WHEN class_id = 15 THEN
        dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 1);
      -- tin_relief
      WHEN class_id = 16 THEN
        dummy_bbox := citydb.env_tin_relief(co_id, set_envelope, 0);
      -- masspoint_relief
      WHEN class_id = 17 THEN
        dummy_bbox := citydb.env_masspoint_relief(co_id, set_envelope, 0);
      -- breakline_relief
      WHEN class_id = 18 THEN
        dummy_bbox := citydb.env_breakline_relief(co_id, set_envelope, 0);
      -- raster_relief
      WHEN class_id = 19 THEN
        dummy_bbox := citydb.env_raster_relief(co_id, set_envelope, 0);
      -- city_furniture
      WHEN class_id = 21 THEN
        dummy_bbox := citydb.env_city_furniture(co_id, set_envelope, 1);
      -- cityobjectgroup
      WHEN class_id = 23 THEN
        dummy_bbox := citydb.env_cityobjectgroup(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 24 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 25 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building
      WHEN class_id = 26 THEN
        dummy_bbox := citydb.env_building(co_id, set_envelope, 1);
      -- building_installation
      WHEN class_id = 27 THEN
        dummy_bbox := citydb.env_building_installation(co_id, set_envelope, 1);
      -- building_installation
      WHEN class_id = 28 THEN
        dummy_bbox := citydb.env_building_installation(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 29 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 30 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 31 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 32 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 33 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 34 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 35 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 36 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 37 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 38 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- opening
      WHEN class_id = 39 THEN
        dummy_bbox := citydb.env_opening(co_id, set_envelope, 1);
      -- building_furniture
      WHEN class_id = 40 THEN
        dummy_bbox := citydb.env_building_furniture(co_id, set_envelope, 1);
      -- room
      WHEN class_id = 41 THEN
        dummy_bbox := citydb.env_room(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 42 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 43 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 44 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 45 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- transportation_complex
      WHEN class_id = 46 THEN
        dummy_bbox := citydb.env_transportation_complex(co_id, set_envelope, 1);
      -- traffic_area
      WHEN class_id = 47 THEN
        dummy_bbox := citydb.env_traffic_area(co_id, set_envelope, 1);
      -- traffic_area
      WHEN class_id = 48 THEN
        dummy_bbox := citydb.env_traffic_area(co_id, set_envelope, 1);
      -- appearance
      WHEN class_id = 50 THEN
        dummy_bbox := citydb.env_appearance(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 51 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 52 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 53 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 54 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- surface_data
      WHEN class_id = 55 THEN
        dummy_bbox := citydb.env_surface_data(co_id, set_envelope, 0);
      -- textureparam
      WHEN class_id = 56 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      -- citymodel
      WHEN class_id = 57 THEN
        dummy_bbox := citydb.env_citymodel(co_id, set_envelope, 0);
      -- address
      WHEN class_id = 58 THEN
        dummy_bbox := citydb.env_address(co_id, set_envelope, 0);
      -- implicit_geometry
      WHEN class_id = 59 THEN
        dummy_bbox := citydb.env_implicit_geometry(co_id, set_envelope, 0);
      -- thematic_surface
      WHEN class_id = 60 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- thematic_surface
      WHEN class_id = 61 THEN
        dummy_bbox := citydb.env_thematic_surface(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 62 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 63 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge
      WHEN class_id = 64 THEN
        dummy_bbox := citydb.env_bridge(co_id, set_envelope, 1);
      -- bridge_installation
      WHEN class_id = 65 THEN
        dummy_bbox := citydb.env_bridge_installation(co_id, set_envelope, 1);
      -- bridge_installation
      WHEN class_id = 66 THEN
        dummy_bbox := citydb.env_bridge_installation(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 67 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 68 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 69 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 70 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 71 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 72 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 73 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 74 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 75 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_thematic_surface
      WHEN class_id = 76 THEN
        dummy_bbox := citydb.env_bridge_thematic_surface(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 77 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 78 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_opening
      WHEN class_id = 79 THEN
        dummy_bbox := citydb.env_bridge_opening(co_id, set_envelope, 1);
      -- bridge_furniture
      WHEN class_id = 80 THEN
        dummy_bbox := citydb.env_bridge_furniture(co_id, set_envelope, 1);
      -- bridge_room
      WHEN class_id = 81 THEN
        dummy_bbox := citydb.env_bridge_room(co_id, set_envelope, 1);
      -- bridge_constr_element
      WHEN class_id = 82 THEN
        dummy_bbox := citydb.env_bridge_constr_element(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 83 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 84 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel
      WHEN class_id = 85 THEN
        dummy_bbox := citydb.env_tunnel(co_id, set_envelope, 1);
      -- tunnel_installation
      WHEN class_id = 86 THEN
        dummy_bbox := citydb.env_tunnel_installation(co_id, set_envelope, 1);
      -- tunnel_installation
      WHEN class_id = 87 THEN
        dummy_bbox := citydb.env_tunnel_installation(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 88 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 89 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 90 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 91 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 92 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 93 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 94 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 95 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 96 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_thematic_surface
      WHEN class_id = 97 THEN
        dummy_bbox := citydb.env_tunnel_thematic_surface(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 98 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 99 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_opening
      WHEN class_id = 100 THEN
        dummy_bbox := citydb.env_tunnel_opening(co_id, set_envelope, 1);
      -- tunnel_furniture
      WHEN class_id = 101 THEN
        dummy_bbox := citydb.env_tunnel_furniture(co_id, set_envelope, 1);
      -- tunnel_hollow_space
      WHEN class_id = 102 THEN
        dummy_bbox := citydb.env_tunnel_hollow_space(co_id, set_envelope, 1);
      -- textureparam
      WHEN class_id = 103 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      -- textureparam
      WHEN class_id = 104 THEN
        dummy_bbox := citydb.env_textureparam(co_id, set_envelope, 0);
      ELSE
    END CASE;
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  IF set_envelope <> 0 THEN
    UPDATE citydb.cityobject SET envelope = bbox WHERE id = co_id;
  END IF;

  RETURN bbox;
END;
$$;
 Y   DROP FUNCTION citydb.env_cityobject(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            k           1255    35076 -   env_cityobjectgroup(bigint, integer, integer)    FUNCTION     J  CREATE FUNCTION citydb.env_cityobjectgroup(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.cityobjectgroup t WHERE sg.root_id = t.brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- geometry
    SELECT other_geom AS geom FROM citydb.cityobjectgroup WHERE id = co_id  AND other_geom IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _CityObject
    SELECT citydb.env_cityobject(c.id, set_envelope) AS geom FROM citydb.cityobject c, citydb.group_to_cityobject p2c WHERE c.id = cityobject_id AND p2c.cityobjectgroup_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 ^   DROP FUNCTION citydb.env_cityobjectgroup(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35077 0   env_generic_cityobject(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_generic_cityobject(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod0_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod0Geometry
    SELECT lod0_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod0_other_geom IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.generic_cityobject t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod0TerrainIntersection
    SELECT lod0_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod0_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.generic_cityobject WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod0ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod0_implicit_rep_id, lod0_implicit_ref_point, lod0_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod0_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.generic_cityobject WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 a   DROP FUNCTION citydb.env_generic_cityobject(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9                       1255    35078 /   env_implicit_geometry(bigint, integer, integer)    FUNCTION     '  CREATE FUNCTION citydb.env_implicit_geometry(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;
 `   DROP FUNCTION citydb.env_implicit_geometry(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35079 &   env_land_use(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_land_use(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod0_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.land_use t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 W   DROP FUNCTION citydb.env_land_use(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35080 .   env_masspoint_relief(bigint, integer, integer)    FUNCTION     $  CREATE FUNCTION citydb.env_masspoint_relief(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- reliefPoints
    SELECT relief_points AS geom FROM citydb.masspoint_relief WHERE id = co_id  AND relief_points IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_masspoint_relief(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            K           1255    35081 %   env_opening(bigint, integer, integer)    FUNCTION     r  CREATE FUNCTION citydb.env_opening(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- Address
    SELECT citydb.env_address(c.id, set_envelope) AS geom FROM citydb.opening p, address c WHERE p.id = co_id AND p.address_id = c.id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 V   DROP FUNCTION citydb.env_opening(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            G           1255    35082 )   env_plant_cover(bigint, integer, integer)    FUNCTION     4	  CREATE FUNCTION citydb.env_plant_cover(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod1_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod2_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod3_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSolid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.plant_cover t WHERE sg.root_id = t.lod4_multi_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 Z   DROP FUNCTION citydb.env_plant_cover(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            	           1255    35083 +   env_raster_relief(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_raster_relief(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  RETURN bbox;
END;
$$;
 \   DROP FUNCTION citydb.env_raster_relief(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35084 .   env_relief_component(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_relief_component(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- extent
    SELECT extent AS geom FROM citydb.relief_component WHERE id = co_id  AND extent IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  IF caller <> 2 THEN
    SELECT objectclass_id INTO class_id FROM citydb.relief_component WHERE id = co_id;
    CASE
      -- tin_relief
      WHEN class_id = 16 THEN
        dummy_bbox := citydb.env_tin_relief(co_id, set_envelope, 1);
      -- masspoint_relief
      WHEN class_id = 17 THEN
        dummy_bbox := citydb.env_masspoint_relief(co_id, set_envelope, 1);
      -- breakline_relief
      WHEN class_id = 18 THEN
        dummy_bbox := citydb.env_breakline_relief(co_id, set_envelope, 1);
      -- raster_relief
      WHEN class_id = 19 THEN
        dummy_bbox := citydb.env_raster_relief(co_id, set_envelope, 1);
      ELSE
    END CASE;
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_relief_component(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35085 ,   env_relief_feature(bigint, integer, integer)    FUNCTION     h  CREATE FUNCTION citydb.env_relief_feature(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _ReliefComponent
    SELECT citydb.env_relief_component(c.id, set_envelope) AS geom FROM citydb.relief_component c, citydb.relief_feat_to_rel_comp p2c WHERE c.id = relief_component_id AND p2c.relief_feature_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 ]   DROP FUNCTION citydb.env_relief_feature(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2                        1255    35086 "   env_room(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_room(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.room t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.room t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_thematic_surface(id, set_envelope) AS geom FROM citydb.thematic_surface WHERE room_id = co_id
      UNION ALL
    -- BuildingFurniture
    SELECT citydb.env_building_furniture(id, set_envelope) AS geom FROM citydb.building_furniture WHERE room_id = co_id
      UNION ALL
    -- IntBuildingInstallation
    SELECT citydb.env_building_installation(id, set_envelope) AS geom FROM citydb.building_installation WHERE room_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 S   DROP FUNCTION citydb.env_room(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            E           1255    35087 5   env_solitary_vegetat_object(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_solitary_vegetat_object(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod1_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Geometry
    SELECT lod1_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod1_other_geom IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.solitary_vegetat_object t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod1ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod1_implicit_rep_id, lod1_implicit_ref_point, lod1_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod1_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.solitary_vegetat_object WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 f   DROP FUNCTION citydb.env_solitary_vegetat_object(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            P           1255    35088 *   env_surface_data(bigint, integer, integer)    FUNCTION     j  CREATE FUNCTION citydb.env_surface_data(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- referencePoint
    SELECT gt_reference_point AS geom FROM citydb.surface_data WHERE id = co_id  AND gt_reference_point IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 [   DROP FUNCTION citydb.env_surface_data(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35089 *   env_textureparam(bigint, integer, integer)    FUNCTION     "  CREATE FUNCTION citydb.env_textureparam(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  RETURN bbox;
END;
$$;
 [   DROP FUNCTION citydb.env_textureparam(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            �           1255    35090 .   env_thematic_surface(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_thematic_surface(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _Opening
    SELECT citydb.env_opening(c.id, set_envelope) AS geom FROM citydb.opening c, citydb.opening_to_them_surface p2c WHERE c.id = opening_id AND p2c.thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_thematic_surface(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            �           1255    35091 (   env_tin_relief(bigint, integer, integer)    FUNCTION     Q  CREATE FUNCTION citydb.env_tin_relief(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_relief_component(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- tin
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tin_relief t WHERE sg.root_id = t.surface_geometry_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 Y   DROP FUNCTION citydb.env_tin_relief(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35092 *   env_traffic_area(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_traffic_area(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.traffic_area t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 [   DROP FUNCTION citydb.env_traffic_area(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            X           1255    35093 4   env_transportation_complex(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_transportation_complex(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0Network
    SELECT lod0_network AS geom FROM citydb.transportation_complex WHERE id = co_id  AND lod0_network IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.transportation_complex t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- TrafficArea
    SELECT citydb.env_traffic_area(id, set_envelope) AS geom FROM citydb.traffic_area WHERE transportation_complex_id = co_id
      UNION ALL
    -- AuxiliaryTrafficArea
    SELECT citydb.env_traffic_area(id, set_envelope) AS geom FROM citydb.traffic_area WHERE transportation_complex_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 e   DROP FUNCTION citydb.env_transportation_complex(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35094 $   env_tunnel(bigint, integer, integer)    FUNCTION       CREATE FUNCTION citydb.env_tunnel(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1TerrainIntersection
    SELECT lod1_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod1_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2MultiCurve
    SELECT lod2_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod2_multi_curve IS NOT NULL
      UNION ALL
    -- lod2TerrainIntersection
    SELECT lod2_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod2_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiCurve
    SELECT lod3_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod3_multi_curve IS NOT NULL
      UNION ALL
    -- lod3TerrainIntersection
    SELECT lod3_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod3_terrain_intersection IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiCurve
    SELECT lod4_multi_curve AS geom FROM citydb.tunnel WHERE id = co_id  AND lod4_multi_curve IS NOT NULL
      UNION ALL
    -- lod4TerrainIntersection
    SELECT lod4_terrain_intersection AS geom FROM citydb.tunnel WHERE id = co_id  AND lod4_terrain_intersection IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- TunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_id = co_id
      UNION ALL
    -- IntTunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_id = co_id
      UNION ALL
    -- HollowSpace
    SELECT citydb.env_tunnel_hollow_space(id, set_envelope) AS geom FROM citydb.tunnel_hollow_space WHERE tunnel_id = co_id
      UNION ALL
    -- TunnelPart
    SELECT citydb.env_tunnel(id, set_envelope) AS geom FROM citydb.tunnel WHERE tunnel_parent_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 U   DROP FUNCTION citydb.env_tunnel(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            b           1255    35095 .   env_tunnel_furniture(bigint, integer, integer)    FUNCTION        CREATE FUNCTION citydb.env_tunnel_furniture(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_furniture t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_furniture WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_furniture WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 _   DROP FUNCTION citydb.env_tunnel_furniture(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            �           1255    35096 1   env_tunnel_hollow_space(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_tunnel_hollow_space(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_hollow_space t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_hollow_space t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_hollow_space_id = co_id
      UNION ALL
    -- TunnelFurniture
    SELECT citydb.env_tunnel_furniture(id, set_envelope) AS geom FROM citydb.tunnel_furniture WHERE tunnel_hollow_space_id = co_id
      UNION ALL
    -- IntTunnelInstallation
    SELECT citydb.env_tunnel_installation(id, set_envelope) AS geom FROM citydb.tunnel_installation WHERE tunnel_hollow_space_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 b   DROP FUNCTION citydb.env_tunnel_hollow_space(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            o           1255    35097 1   env_tunnel_installation(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_tunnel_installation(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod2_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Geometry
    SELECT lod2_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod2_other_geom IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod3_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Geometry
    SELECT lod3_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod3_other_geom IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod2ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod2_implicit_rep_id, lod2_implicit_ref_point, lod2_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod2_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_installation t WHERE sg.root_id = t.lod4_brep_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Geometry
    SELECT lod4_other_geom AS geom FROM citydb.tunnel_installation WHERE id = co_id  AND lod4_other_geom IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_installation WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_installation_id = co_id
      UNION ALL
    -- _BoundarySurface
    SELECT citydb.env_tunnel_thematic_surface(id, set_envelope) AS geom FROM citydb.tunnel_thematic_surface WHERE tunnel_installation_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 b   DROP FUNCTION citydb.env_tunnel_installation(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            D           1255    35098 ,   env_tunnel_opening(bigint, integer, integer)    FUNCTION     U  CREATE FUNCTION citydb.env_tunnel_opening(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_opening t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_opening t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod3_implicit_rep_id, lod3_implicit_ref_point, lod3_implicit_transformation) AS geom FROM citydb.tunnel_opening WHERE id = co_id AND lod3_implicit_rep_id IS NOT NULL
      UNION ALL
    -- lod4ImplicitRepresentation
    SELECT citydb.get_envelope_implicit_geometry(lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) AS geom FROM citydb.tunnel_opening WHERE id = co_id AND lod4_implicit_rep_id IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 ]   DROP FUNCTION citydb.env_tunnel_opening(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            M           1255    35099 5   env_tunnel_thematic_surface(bigint, integer, integer)    FUNCTION     �  CREATE FUNCTION citydb.env_tunnel_thematic_surface(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod2_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod3_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.tunnel_thematic_surface t WHERE sg.root_id = t.lod4_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _Opening
    SELECT citydb.env_tunnel_opening(c.id, set_envelope) AS geom FROM citydb.tunnel_opening c, citydb.tunnel_open_to_them_srf p2c WHERE c.id = tunnel_opening_id AND p2c.tunnel_thematic_surface_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 f   DROP FUNCTION citydb.env_tunnel_thematic_surface(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9                       1255    35100 '   env_waterbody(bigint, integer, integer)    FUNCTION     
  CREATE FUNCTION citydb.env_waterbody(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod0MultiCurve
    SELECT lod0_multi_curve AS geom FROM citydb.waterbody WHERE id = co_id  AND lod0_multi_curve IS NOT NULL
      UNION ALL
    -- lod0MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod0_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1MultiCurve
    SELECT lod1_multi_curve AS geom FROM citydb.waterbody WHERE id = co_id  AND lod1_multi_curve IS NOT NULL
      UNION ALL
    -- lod1MultiSurface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod1_multi_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod1Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod1_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod2Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod2_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod3_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Solid
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterbody t WHERE sg.root_id = t.lod4_solid_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  -- bbox from aggregating objects
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- _WaterBoundarySurface
    SELECT citydb.env_waterboundary_surface(c.id, set_envelope) AS geom FROM citydb.waterboundary_surface c, citydb.waterbod_to_waterbnd_srf p2c WHERE c.id = waterboundary_surface_id AND p2c.waterbody_id = co_id
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 X   DROP FUNCTION citydb.env_waterbody(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9                       1255    35101 3   env_waterboundary_surface(bigint, integer, integer)    FUNCTION       CREATE FUNCTION citydb.env_waterboundary_surface(co_id bigint, set_envelope integer DEFAULT 0, caller integer DEFAULT 0) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $$
DECLARE
  class_id INTEGER DEFAULT 0;
  bbox GEOMETRY;
  dummy_bbox GEOMETRY;
BEGIN
  -- bbox from parent table
  IF caller <> 1 THEN
    dummy_bbox := citydb.env_cityobject(co_id, set_envelope, 2);
    bbox := citydb.update_bounds(bbox, dummy_bbox);
  END IF;

  -- bbox from inline and referencing spatial columns
  SELECT citydb.box2envelope(ST_3DExtent(geom)) INTO dummy_bbox FROM (
    -- lod2Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod2_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod3Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod3_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
      UNION ALL
    -- lod4Surface
    SELECT sg.geometry AS geom FROM citydb.surface_geometry sg, citydb.waterboundary_surface t WHERE sg.root_id = t.lod4_surface_id AND t.id = co_id AND sg.geometry IS NOT NULL
  ) g;
  bbox := citydb.update_bounds(bbox, dummy_bbox);

  RETURN bbox;
END;
$$;
 d   DROP FUNCTION citydb.env_waterboundary_surface(co_id bigint, set_envelope integer, caller integer);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            r           1255    35102 3   get_envelope_cityobjects(integer, integer, integer)    FUNCTION     N  CREATE FUNCTION citydb.get_envelope_cityobjects(objclass_id integer DEFAULT 0, set_envelope integer DEFAULT 0, only_if_null integer DEFAULT 1) RETURNS public.geometry
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  bbox GEOMETRY;
  filter TEXT;
BEGIN
  IF only_if_null <> 0 THEN
    filter := ' WHERE envelope IS NULL';
  END IF;

  IF objclass_id <> 0 THEN
    IF filter IS NULL THEN
      filter := ' WHERE ';
    ELSE
      filter := filter || ' AND ';
    END IF;
    filter := filter || 'objectclass_id = ' || objclass_id::TEXT;
  END IF;

  IF filter IS NULL THEN
    filter := '';
  END IF;

  EXECUTE 'SELECT citydb.box2envelope(ST_3DExtent(geom)) FROM (
    SELECT citydb.env_cityobject(id, $1) AS geom
      FROM citydb.cityobject' || filter || ')g' INTO bbox USING set_envelope; 

  RETURN bbox;
END;
$_$;
 p   DROP FUNCTION citydb.get_envelope_cityobjects(objclass_id integer, set_envelope integer, only_if_null integer);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            d           1255    35103 J   get_envelope_implicit_geometry(bigint, public.geometry, character varying)    FUNCTION     >  CREATE FUNCTION citydb.get_envelope_implicit_geometry(implicit_rep_id bigint, ref_pt public.geometry, transform4x4 character varying) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  envelope GEOMETRY;
  params DOUBLE PRECISION[ ] := '{}';
BEGIN
  -- calculate bounding box for implicit geometry

  SELECT box2envelope(ST_3DExtent(geom)) INTO envelope FROM (
    -- relative other geometry

    SELECT relative_other_geom AS geom 
      FROM citydb.implicit_geometry
        WHERE id = implicit_rep_id
          AND relative_other_geom IS NOT NULL
    UNION ALL
    -- relative brep geometry
    SELECT sg.implicit_geometry AS geom
      FROM citydb.surface_geometry sg, citydb.implicit_geometry ig
        WHERE sg.root_id = ig.relative_brep_id 
          AND ig.id = implicit_rep_id 
          AND sg.implicit_geometry IS NOT NULL
  ) g;

  IF transform4x4 IS NOT NULL THEN
    -- -- extract parameters of transformation matrix
    params := string_to_array(transform4x4, ' ')::float8[];

    IF array_length(params, 1) < 12 THEN
      RAISE EXCEPTION 'Malformed transformation matrix: %', transform4x4 USING HINT = '16 values are required';
    END IF; 
  ELSE
    params := '{
      1, 0, 0, 0,
      0, 1, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1}';
  END IF;

  IF ref_pt IS NOT NULL THEN
    params[4] := params[4] + ST_X(ref_pt);
    params[8] := params[8] + ST_Y(ref_pt);
    params[12] := params[12] + ST_Z(ref_pt);
  END IF;

  IF envelope IS NOT NULL THEN
    -- perform affine transformation against given transformation matrix
    envelope := ST_Affine(envelope,
      params[1], params[2], params[3],
      params[5], params[6], params[7],
      params[9], params[10], params[11],
      params[4], params[8], params[12]);
  END IF;

  RETURN envelope;
END;
$$;
 �   DROP FUNCTION citydb.get_envelope_implicit_geometry(implicit_rep_id bigint, ref_pt public.geometry, transform4x4 character varying);
       citydb          postgres    false    2    2    2    2    2    2    2    2    9            �           1255    35056 %   objectclass_id_to_table_name(integer)    FUNCTION     �   CREATE FUNCTION citydb.objectclass_id_to_table_name(class_id integer) RETURNS text
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT
  tablename
FROM
  objectclass
WHERE
  id = $1;
$_$;
 E   DROP FUNCTION citydb.objectclass_id_to_table_name(class_id integer);
       citydb          postgres    false    9            n           1255    35057 #   table_name_to_objectclass_ids(text)    FUNCTION       CREATE FUNCTION citydb.table_name_to_objectclass_ids(table_name text) RETURNS integer[]
    LANGUAGE sql STABLE STRICT
    AS $_$
WITH RECURSIVE objectclass_tree (id, superclass_id) AS (
  SELECT
    id,
    superclass_id
  FROM
    objectclass
  WHERE
    tablename = lower($1)
  UNION ALL
    SELECT
      o.id,
      o.superclass_id
    FROM
      objectclass o,
      objectclass_tree t
    WHERE
      o.superclass_id = t.id
)
SELECT
  array_agg(DISTINCT id ORDER BY id)
FROM
  objectclass_tree;
$_$;
 E   DROP FUNCTION citydb.table_name_to_objectclass_ids(table_name text);
       citydb          postgres    false    9            �           1255    35104 /   update_bounds(public.geometry, public.geometry)    FUNCTION       CREATE FUNCTION citydb.update_bounds(old_box public.geometry, new_box public.geometry) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  updated_box GEOMETRY;
BEGIN
  IF old_box IS NULL AND new_box IS NULL THEN
    RETURN NULL;
  ELSE
    IF old_box IS NULL THEN
      RETURN new_box;
    END IF;

    IF new_box IS NULL THEN
      RETURN old_box;
    END IF;

    updated_box := citydb.box2envelope(ST_3DExtent(ST_Collect(old_box, new_box)));
  END IF;

  RETURN updated_box;
END;
$$;
 V   DROP FUNCTION citydb.update_bounds(old_box public.geometry, new_box public.geometry);
       citydb          postgres    false    9    2    2    2    2    2    2    2    2            �           1255    35239 E   change_column_srid(text, text, integer, integer, integer, text, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.change_column_srid(table_name text, column_name text, dim integer, schema_srid integer, transform integer DEFAULT 0, geom_type text DEFAULT 'GEOMETRY'::text, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_name TEXT;
  opclass_param TEXT;
  geometry_type TEXT;
BEGIN
  -- check if a spatial index is defined for the column
  SELECT 
    pgc_i.relname,
    pgoc.opcname
  INTO
    idx_name,
    opclass_param
  FROM pg_class pgc_t
  JOIN pg_index pgi ON pgi.indrelid = pgc_t.oid  
  JOIN pg_class pgc_i ON pgc_i.oid = pgi.indexrelid
  JOIN pg_opclass pgoc ON pgoc.oid = pgi.indclass[0]
  JOIN pg_am pgam ON pgam.oid = pgc_i.relam
  JOIN pg_attribute pga ON pga.attrelid = pgc_i.oid
  JOIN pg_namespace pgns ON pgns.oid = pgc_i.relnamespace
  WHERE pgns.nspname = lower($7)
    AND pgc_t.relname = lower($1)
    AND pga.attname = lower($2)
    AND pgam.amname = 'gist';

  IF idx_name IS NOT NULL THEN
    -- drop spatial index if exists
    EXECUTE format('DROP INDEX %I.%I', $7, idx_name);
  END IF;

  IF transform <> 0 THEN
    -- construct correct geometry type
    IF dim = 3 AND substr($6,length($6),length($6)) <> 'M' THEN
      geometry_type := $6 || 'Z';
    ELSIF dim = 4 THEN
      geometry_type := $6 || 'ZM';
    ELSE
      geometry_type := $6;
    END IF;

    -- coordinates of existent geometries will be transformed
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I TYPE geometry(%I,%L) USING ST_Transform(%I,%L::int)',
                     $7, $1, $2, geometry_type, $4, $2, $4);
  ELSE
    -- only metadata of geometry columns is updated, coordinates keep unchanged
    PERFORM UpdateGeometrySRID($7, $1, $2, $4);
  END IF;

  IF idx_name IS NOT NULL THEN
    -- recreate spatial index again
    EXECUTE format('CREATE INDEX %I ON %I.%I USING GIST (%I %I)', idx_name, $7, $1, $2, opclass_param);
  END IF;
END;
$_$;
 �   DROP FUNCTION citydb_pkg.change_column_srid(table_name text, column_name text, dim integer, schema_srid integer, transform integer, geom_type text, schema_name text);
    
   citydb_pkg          postgres    false    10            ,           1255    35240 0   change_schema_srid(integer, text, integer, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.change_schema_srid(schema_srid integer, schema_gml_srs_name text, transform integer DEFAULT 0, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
BEGIN
  -- check if user selected srid is valid
  -- will raise an exception if not
  PERFORM citydb_pkg.check_srid($1);

  -- update entry in database_srs table first
  EXECUTE format('TRUNCATE TABLE %I.database_srs', $4);
  EXECUTE format('INSERT INTO %I.database_srs (srid, gml_srs_name) VALUES (%L, %L)', $4, $1, $2);

  -- change srid of spatial columns in given schema
  PERFORM citydb_pkg.change_column_srid(f_table_name, f_geometry_column, coord_dimension, $1, $3, type, f_table_schema)
    FROM geometry_columns
    WHERE f_table_schema = lower($4)
      AND f_geometry_column <> 'implicit_geometry'
      AND f_geometry_column <> 'relative_other_geom'
      AND f_geometry_column <> 'texture_coordinates';
END;
$_$;
 �   DROP FUNCTION citydb_pkg.change_schema_srid(schema_srid integer, schema_gml_srs_name text, transform integer, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35237    check_srid(integer)    FUNCTION     �  CREATE FUNCTION citydb_pkg.check_srid(srsno integer DEFAULT 0) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  schema_srid INTEGER;
BEGIN
  SELECT srid INTO schema_srid FROM spatial_ref_sys WHERE srid = $1;

  IF schema_srid IS NULL THEN
    RAISE EXCEPTION 'Table spatial_ref_sys does not contain the SRID %. Insert commands for missing SRIDs can be found at spatialreference.org', srsno;
    RETURN 'SRID not ok';
  END IF;

  RETURN 'SRID ok';
END;
$_$;
 4   DROP FUNCTION citydb_pkg.check_srid(srsno integer);
    
   citydb_pkg          postgres    false    10            �           1255    35206    citydb_version()    FUNCTION     4  CREATE FUNCTION citydb_pkg.citydb_version(OUT version text, OUT major_version integer, OUT minor_version integer, OUT minor_revision integer) RETURNS record
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 
  '4.4.0'::text AS version,
  4 AS major_version, 
  4 AS minor_version,
  0 AS minor_revision;
$$;
 �   DROP FUNCTION citydb_pkg.citydb_version(OUT version text, OUT major_version integer, OUT minor_version integer, OUT minor_revision integer);
    
   citydb_pkg          postgres    false    10            �           1255    35221 +   construct_normal(text, text, text, integer)    FUNCTION     �   CREATE FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 0, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;
 e   DROP FUNCTION citydb_pkg.construct_normal(ind_name text, tab_name text, att_name text, crs integer);
    
   citydb_pkg          postgres    false    2677    10            �           1255    35220 /   construct_spatial_2d(text, text, text, integer)    FUNCTION     �   CREATE FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 0)::citydb_pkg.INDEX_OBJ;
$_$;
 i   DROP FUNCTION citydb_pkg.construct_spatial_2d(ind_name text, tab_name text, att_name text, crs integer);
    
   citydb_pkg          postgres    false    10    2677            
           1255    35219 /   construct_spatial_3d(text, text, text, integer)    FUNCTION     �   CREATE FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer DEFAULT 0) RETURNS citydb_pkg.index_obj
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT ($1, $2, $3, 1, $4, 1)::citydb_pkg.INDEX_OBJ;
$_$;
 i   DROP FUNCTION citydb_pkg.construct_spatial_3d(ind_name text, tab_name text, att_name text, crs integer);
    
   citydb_pkg          postgres    false    10    2677            �           1255    35224 (   create_index(citydb_pkg.index_obj, text)    FUNCTION     j  CREATE FUNCTION citydb_pkg.create_index(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  create_ddl TEXT;
  SPATIAL CONSTANT NUMERIC(1) := 1;
BEGIN
  IF citydb_pkg.index_status($1, $2) <> 'VALID' THEN
    PERFORM citydb_pkg.drop_index($1, $2);

    BEGIN
      IF ($1).type = SPATIAL THEN
        IF ($1).is_3d = 1 THEN
          EXECUTE format(
            'CREATE INDEX %I ON %I.%I USING GIST (%I gist_geometry_ops_nd)',
            ($1).index_name, $2, ($1).table_name, ($1).attribute_name);
        ELSE
          EXECUTE format(
            'CREATE INDEX %I ON %I.%I USING GIST (%I gist_geometry_ops_2d)',
            ($1).index_name, $2, ($1).table_name, ($1).attribute_name);
        END IF;
      ELSE
        EXECUTE format(
          'CREATE INDEX %I ON %I.%I USING BTREE ('|| idx.attribute_name || ')',
          idx.index_name, schema_name, idx.table_name);
      END IF;

      EXCEPTION
        WHEN OTHERS THEN
          RETURN SQLSTATE || ' - ' || SQLERRM;
    END;
  END IF;

  RETURN '0';
END;
$_$;
 S   DROP FUNCTION citydb_pkg.create_index(idx citydb_pkg.index_obj, schema_name text);
    
   citydb_pkg          postgres    false    10    2677            �           1255    35226    create_indexes(integer, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.create_indexes(idx_type integer, schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
  sql_error_msg TEXT;
  rec RECORD;
BEGIN
  FOR rec IN EXECUTE format('
    SELECT * FROM %I.index_table WHERE (obj).type = %L', $2, $1)
  LOOP
    sql_error_msg := citydb_pkg.create_index(rec.obj, $2);
    idx_log := array_append(
      idx_log,
      citydb_pkg.index_status(rec.obj, $2)
      || ':' || (rec.obj).index_name
      || ':' || $2
      || ':' || (rec.obj).table_name
      || ':' || (rec.obj).attribute_name
      || ':' || sql_error_msg
    );
  END LOOP;

  RETURN idx_log;
END;
$_$;
 M   DROP FUNCTION citydb_pkg.create_indexes(idx_type integer, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35232    create_normal_indexes(text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.create_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(0, $1);
$_$;
 B   DROP FUNCTION citydb_pkg.create_normal_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10                       1255    35230    create_spatial_indexes(text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.create_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.create_indexes(1, $1);
$_$;
 C   DROP FUNCTION citydb_pkg.create_spatial_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35209    db_info(text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.db_info(schema_name text DEFAULT 'citydb'::text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT versioning text) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  EXECUTE format(
    'SELECT 
       srid, gml_srs_name, citydb_pkg.versioning_db($1)
     FROM
       %I.database_srs', schema_name)
    USING schema_name
    INTO schema_srid, schema_gml_srs_name, versioning;
END;
$_$;
 �   DROP FUNCTION citydb_pkg.db_info(schema_name text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT versioning text);
    
   citydb_pkg          postgres    false    10            �           1255    35210    db_metadata(text)    FUNCTION       CREATE FUNCTION citydb_pkg.db_metadata(schema_name text DEFAULT 'citydb'::text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT coord_ref_sys_name text, OUT coord_ref_sys_kind text, OUT wktext text, OUT versioning text) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  EXECUTE format(
    'SELECT 
       d.srid,
       d.gml_srs_name,
       split_part(s.srtext, ''"'', 2),
       split_part(s.srtext, ''['', 1),
       s.srtext,
       citydb_pkg.versioning_db($1) AS versioning
     FROM 
       %I.database_srs d,
       spatial_ref_sys s 
     WHERE
       d.srid = s.srid', schema_name)
    USING schema_name
    INTO schema_srid, schema_gml_srs_name, coord_ref_sys_name, coord_ref_sys_kind, wktext, versioning;
END;
$_$;
 �   DROP FUNCTION citydb_pkg.db_metadata(schema_name text, OUT schema_srid integer, OUT schema_gml_srs_name text, OUT coord_ref_sys_name text, OUT coord_ref_sys_kind text, OUT wktext text, OUT versioning text);
    
   citydb_pkg          postgres    false    10            �           1255    35225 &   drop_index(citydb_pkg.index_obj, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.drop_index(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  index_name TEXT;
BEGIN
  IF citydb_pkg.index_status($1, $2) <> 'DROPPED' THEN
    BEGIN
      EXECUTE format(
        'DROP INDEX IF EXISTS %I.%I',
        $2, ($1).index_name);

      EXCEPTION
        WHEN OTHERS THEN
          RETURN SQLSTATE || ' - ' || SQLERRM;
    END;
  END IF;

  RETURN '0';
END;
$_$;
 Q   DROP FUNCTION citydb_pkg.drop_index(idx citydb_pkg.index_obj, schema_name text);
    
   citydb_pkg          postgres    false    2677    10            �           1255    35227    drop_indexes(integer, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.drop_indexes(idx_type integer, schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
  sql_error_msg TEXT;
  rec RECORD;
BEGIN
  FOR rec IN EXECUTE format('
    SELECT * FROM %I.index_table WHERE (obj).type = %L', $2, $1)
  LOOP
    sql_error_msg := citydb_pkg.drop_index(rec.obj, $2);
    idx_log := array_append(
      idx_log,
      citydb_pkg.index_status(rec.obj, $2)
      || ':' || (rec.obj).index_name
      || ':' || $2
      || ':' || (rec.obj).table_name
      || ':' || (rec.obj).attribute_name
      || ':' || sql_error_msg
    );
  END LOOP;

  RETURN idx_log;
END;
$_$;
 K   DROP FUNCTION citydb_pkg.drop_indexes(idx_type integer, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35233    drop_normal_indexes(text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.drop_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(0, $1); 
$_$;
 @   DROP FUNCTION citydb_pkg.drop_normal_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10                       1255    35231    drop_spatial_indexes(text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STRICT
    AS $_$
SELECT citydb_pkg.drop_indexes(1, $1);
$_$;
 A   DROP FUNCTION citydb_pkg.drop_spatial_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10            *           1255    35213    drop_tmp_tables(text)    FUNCTION     ~  CREATE FUNCTION citydb_pkg.drop_tmp_tables(schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name LIKE 'tmp_%' LOOP
    EXECUTE format('DROP TABLE %I.%I', $1, rec.table_name); 	
  END LOOP; 
END;
$_$;
 <   DROP FUNCTION citydb_pkg.drop_tmp_tables(schema_name text);
    
   citydb_pkg          postgres    false    10            R           1255    35234    get_index(text, text, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.get_index(idx_table_name text, idx_column_name text, schema_name text DEFAULT 'citydb'::text) RETURNS citydb_pkg.index_obj
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  index_name TEXT;
  table_name TEXT;
  attribute_name TEXT;
  type NUMERIC(1);
  srid INTEGER;
  is_3d NUMERIC(1, 0);
BEGIN
  EXECUTE format('
		SELECT
		  (obj).index_name,
		  (obj).table_name,
		  (obj).attribute_name,
		  (obj).type,
		  (obj).srid,
		  (obj).is_3d
		FROM
		  %I.index_table 
		WHERE
		  (obj).table_name = lower($1)
		  AND (obj).attribute_name = lower($2)', $3)
      INTO index_name, table_name, attribute_name, type, srid, is_3d
      USING idx_table_name, idx_column_name;

  IF index_name IS NOT NULL THEN
    RETURN (index_name, table_name, attribute_name, type, srid, is_3d)::citydb_pkg.INDEX_OBJ;
  ELSE
    RETURN NULL;
  END IF;
END;
$_$;
 a   DROP FUNCTION citydb_pkg.get_index(idx_table_name text, idx_column_name text, schema_name text);
    
   citydb_pkg          postgres    false    10    2677            �           1255    35212    get_seq_values(text, bigint)    FUNCTION     �   CREATE FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count bigint) RETURNS SETOF bigint
    LANGUAGE sql STRICT
    AS $_$
SELECT nextval($1)::bigint FROM generate_series(1, $2);
$_$;
 J   DROP FUNCTION citydb_pkg.get_seq_values(seq_name text, seq_count bigint);
    
   citydb_pkg          postgres    false    10            �           1255    35222 (   index_status(citydb_pkg.index_obj, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.index_status(idx citydb_pkg.index_obj, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  is_valid BOOLEAN;
  status TEXT;
BEGIN
  SELECT
    pgi.indisvalid
  INTO
    is_valid
  FROM
    pg_index pgi
  JOIN
    pg_class pgc
    ON pgc.oid = pgi.indexrelid
  JOIN
    pg_namespace pgn
    ON pgn.oid = pgc.relnamespace
  WHERE
    pgn.nspname = $2
    AND pgc.relname = ($1).index_name;

  IF is_valid is null THEN
    status := 'DROPPED';
  ELSIF is_valid = true THEN
    status := 'VALID';
  ELSE
    status := 'INVALID';
  END IF;

  RETURN status;

  EXCEPTION
    WHEN OTHERS THEN
      RETURN 'FAILED';
END;
$_$;
 S   DROP FUNCTION citydb_pkg.index_status(idx citydb_pkg.index_obj, schema_name text);
    
   citydb_pkg          postgres    false    2677    10                       1255    35223    index_status(text, text, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.index_status(idx_table_name text, idx_column_name text, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  is_valid BOOLEAN;
  status TEXT;
BEGIN
  SELECT
    pgi.indisvalid
  INTO
    is_valid
  FROM
    pg_index pgi
  JOIN
    pg_attribute pga
    ON pga.attrelid = pgi.indexrelid
  WHERE
    pgi.indrelid = (lower($3) || '.' || lower($1))::regclass::oid
    AND pga.attname = lower($2);

  IF is_valid is null THEN
    status := 'DROPPED';
  ELSIF is_valid = true THEN
    status := 'VALID';
  ELSE
    status := 'INVALID';
  END IF;

  RETURN status;

  EXCEPTION
    WHEN OTHERS THEN
      RETURN 'FAILED';
END;
$_$;
 d   DROP FUNCTION citydb_pkg.index_status(idx_table_name text, idx_column_name text, schema_name text);
    
   citydb_pkg          postgres    false    10            M           1255    35235    is_coord_ref_sys_3d(integer)    FUNCTION     �   CREATE FUNCTION citydb_pkg.is_coord_ref_sys_3d(schema_srid integer) RETURNS integer
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT COALESCE((
  SELECT 1 FROM spatial_ref_sys WHERE auth_srid = $1 AND srtext LIKE '%UP]%'
  ), 0);
$_$;
 C   DROP FUNCTION citydb_pkg.is_coord_ref_sys_3d(schema_srid integer);
    
   citydb_pkg          postgres    false    10            C           1255    35236    is_db_coord_ref_sys_3d(text)    FUNCTION     [  CREATE FUNCTION citydb_pkg.is_db_coord_ref_sys_3d(schema_name text DEFAULT 'citydb'::text) RETURNS integer
    LANGUAGE plpgsql STABLE STRICT
    AS $$
DECLARE
  is_3d INTEGER := 0;
BEGIN  
  EXECUTE format(
    'SELECT citydb_pkg.is_coord_ref_sys_3d(srid) FROM %I.database_srs', schema_name
  )
  INTO is_3d;

  RETURN is_3d;
END;
$$;
 C   DROP FUNCTION citydb_pkg.is_db_coord_ref_sys_3d(schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35211    min(numeric, numeric)    FUNCTION     �   CREATE FUNCTION citydb_pkg.min(a numeric, b numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT LEAST($1,$2);
$_$;
 4   DROP FUNCTION citydb_pkg.min(a numeric, b numeric);
    
   citydb_pkg          postgres    false    10                       1255    35216    set_enabled_fkey(oid, boolean)    FUNCTION     l  CREATE FUNCTION citydb_pkg.set_enabled_fkey(fkey_trigger_oid oid, enable boolean DEFAULT true) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  tgstatus char(1);
BEGIN
  IF $2 THEN
    tgstatus := 'O';
  ELSE
    tgstatus := 'D';
  END IF;

  UPDATE
    pg_trigger
  SET
    tgenabled = tgstatus
  WHERE
    oid = $1;
END;
$_$;
 Q   DROP FUNCTION citydb_pkg.set_enabled_fkey(fkey_trigger_oid oid, enable boolean);
    
   citydb_pkg          postgres    false    10            �           1255    35217 %   set_enabled_geom_fkeys(boolean, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.set_enabled_geom_fkeys(enable boolean DEFAULT true, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_enabled_fkey(
    t.oid,
    $1
  )
FROM
  pg_constraint c
JOIN
  pg_trigger t
  ON t.tgconstraint = c.oid
WHERE
  c.contype = 'f'
  AND c.confrelid = (lower($2) || '.surface_geometry')::regclass::oid
  AND c.confdeltype <> 'c'
$_$;
 S   DROP FUNCTION citydb_pkg.set_enabled_geom_fkeys(enable boolean, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35218 '   set_enabled_schema_fkeys(boolean, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.set_enabled_schema_fkeys(enable boolean DEFAULT true, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_enabled_fkey(
    t.oid,
    $1
  )
FROM
  pg_constraint c
JOIN
  pg_namespace n
  ON n.oid = c.connamespace
JOIN
  pg_trigger t
  ON t.tgconstraint = c.oid
WHERE
  c.contype = 'f'
  AND c.confdeltype <> 'c'
  AND n.nspname = $2;
$_$;
 U   DROP FUNCTION citydb_pkg.set_enabled_schema_fkeys(enable boolean, schema_name text);
    
   citydb_pkg          postgres    false    10                       1255    35214 C   set_fkey_delete_rule(text, text, text, text, text, character, text)    FUNCTION     s  CREATE FUNCTION citydb_pkg.set_fkey_delete_rule(fkey_name text, table_name text, column_name text, ref_table text, ref_column text, on_delete_param character DEFAULT 'a'::bpchar, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  delete_param VARCHAR(9);
BEGIN
  CASE on_delete_param
    WHEN 'r' THEN delete_param := 'RESTRICT';
    WHEN 'c' THEN delete_param := 'CASCADE';
    WHEN 'n' THEN delete_param := 'SET NULL';
    ELSE delete_param := 'NO ACTION';
  END CASE;

  EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I, ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I (%I) MATCH FULL
                    ON UPDATE CASCADE ON DELETE ' || delete_param, $7, $2, $1, $1, $3, $7, $4, $5);

  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'Error on constraint %: %', fkey_name, SQLERRM;
END;
$_$;
 �   DROP FUNCTION citydb_pkg.set_fkey_delete_rule(fkey_name text, table_name text, column_name text, ref_table text, ref_column text, on_delete_param character, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35215 -   set_schema_fkeys_delete_rule(character, text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.set_schema_fkeys_delete_rule(on_delete_param character DEFAULT 'a'::bpchar, schema_name text DEFAULT 'citydb'::text) RETURNS SETOF void
    LANGUAGE sql STRICT
    AS $_$
SELECT
  citydb_pkg.set_fkey_delete_rule(
    c.conname,
    c.conrelid::regclass::text,
    a.attname,
    t.relname,
    a_ref.attname,
    $1,
    n.nspname
  )
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
JOIN pg_attribute a_ref ON a_ref.attrelid = c.confrelid AND a_ref.attnum = ANY (c.confkey)
JOIN pg_class t ON t.oid = a_ref.attrelid
JOIN pg_namespace n ON n.oid = c.connamespace
  WHERE n.nspname = $2
    AND c.contype = 'f';
$_$;
 d   DROP FUNCTION citydb_pkg.set_schema_fkeys_delete_rule(on_delete_param character, schema_name text);
    
   citydb_pkg          postgres    false    10                       1255    35229    status_normal_indexes(text)    FUNCTION     m  CREATE FUNCTION citydb_pkg.status_normal_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
BEGIN
	EXECUTE format('
		SELECT
		  array_agg(
		    concat(citydb_pkg.index_status(obj,' || '''%I''' || '),' || ''':''' || ',' ||
		    '(obj).index_name,' || ''':''' || ',' ||
		    '''%I'',' || ''':''' || ',' ||		    
		    '(obj).table_name,' || ''':''' || ',' ||
		    '(obj).attribute_name
		  )) AS log
		FROM
		  %I.index_table
		WHERE
		  (obj).type = 0',$1, $1, $1) INTO idx_log;
		  
	RETURN idx_log;
END;
$_$;
 B   DROP FUNCTION citydb_pkg.status_normal_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35228    status_spatial_indexes(text)    FUNCTION     n  CREATE FUNCTION citydb_pkg.status_spatial_indexes(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE plpgsql STRICT
    AS $_$
DECLARE
  idx_log text[] := '{}';
BEGIN
	EXECUTE format('
		SELECT
		  array_agg(
		    concat(citydb_pkg.index_status(obj,' || '''%I''' || '),' || ''':''' || ',' ||
		    '(obj).index_name,' || ''':''' || ',' ||
		    '''%I'',' || ''':''' || ',' ||		    
		    '(obj).table_name,' || ''':''' || ',' ||
		    '(obj).attribute_name
		  )) AS log
		FROM
		  %I.index_table
		WHERE
		  (obj).type = 1',$1, $1, $1) INTO idx_log;
	  
  RETURN idx_log;
END;
$_$;
 C   DROP FUNCTION citydb_pkg.status_spatial_indexes(schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35241    table_content(text, text)    FUNCTION       CREATE FUNCTION citydb_pkg.table_content(table_name text, schema_name text DEFAULT 'citydb'::text) RETURNS bigint
    LANGUAGE plpgsql STABLE STRICT
    AS $_$
DECLARE
  cnt BIGINT;  
BEGIN
  EXECUTE format('SELECT count(*) FROM %I.%I', $2, $1) INTO cnt;
  RETURN cnt;
END;
$_$;
 K   DROP FUNCTION citydb_pkg.table_content(table_name text, schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35242    table_contents(text)    FUNCTION     �  CREATE FUNCTION citydb_pkg.table_contents(schema_name text DEFAULT 'citydb'::text) RETURNS text[]
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT 
  array_cat(
    ARRAY[
      'Database Report on 3D City Model - Report date: ' || to_char(now()::timestamp, 'DD.MM.YYYY HH24:MI:SS'),
      '==================================================================='
    ],
    array_agg(t.tab)
  ) AS report
FROM (
  SELECT
    '#' || upper(table_name) || (
    CASE WHEN length(table_name) < 7 THEN E'\t\t\t\t'
      WHEN length(table_name) > 6 AND length(table_name) < 15 THEN E'\t\t\t'
      WHEN length(table_name) > 14 AND length(table_name) < 23 THEN E'\t\t'
      WHEN length(table_name) > 22 THEN E'\t'
    END
    ) || citydb_pkg.table_content(table_name, $1) AS tab 
  FROM
    information_schema.tables
  WHERE 
    table_schema = $1
    AND table_name != 'database_srs' 
    AND table_name != 'objectclass'
    AND table_name != 'ade'
    AND table_name != 'schema'
    AND table_name != 'schema_to_objectclass' 
    AND table_name != 'schema_referencing'
    AND table_name != 'aggregation_info'
    AND table_name != 'index_table'
    AND table_name NOT LIKE 'tmp_%'
  ORDER BY
    table_name ASC
) t
$_$;
 ;   DROP FUNCTION citydb_pkg.table_contents(schema_name text);
    
   citydb_pkg          postgres    false    10            /           1255    35238 +   transform_or_null(public.geometry, integer)    FUNCTION       CREATE FUNCTION citydb_pkg.transform_or_null(geom public.geometry, srid integer) RETURNS public.geometry
    LANGUAGE plpgsql STABLE
    AS $_$
BEGIN
  IF geom IS NOT NULL THEN
    RETURN ST_Transform($1, $2);
  ELSE
    RETURN NULL;
  END IF;
END;
$_$;
 P   DROP FUNCTION citydb_pkg.transform_or_null(geom public.geometry, srid integer);
    
   citydb_pkg          postgres    false    10    2    2    2    2    2    2    2    2            �           1255    35208    versioning_db(text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.versioning_db(schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;
 :   DROP FUNCTION citydb_pkg.versioning_db(schema_name text);
    
   citydb_pkg          postgres    false    10            �           1255    35207    versioning_table(text, text)    FUNCTION     �   CREATE FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text DEFAULT 'citydb'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT 'OFF'::text;
$$;
 N   DROP FUNCTION citydb_pkg.versioning_table(table_name text, schema_name text);
    
   citydb_pkg          postgres    false    10            �            1259    32807    address_seq    SEQUENCE     s   CREATE SEQUENCE citydb.address_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 "   DROP SEQUENCE citydb.address_seq;
       citydb          postgres    false    9            +           1259    33111    address    TABLE     �  CREATE TABLE citydb.address (
    id bigint DEFAULT nextval('citydb.address_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    street character varying(1000),
    house_number character varying(256),
    po_box character varying(256),
    zip_code character varying(256),
    city character varying(256),
    state character varying(256),
    country character varying(256),
    multi_point public.geometry(MultiPointZ,32748),
    xal_source text
);
    DROP TABLE citydb.address;
       citydb         heap    postgres    false    249    2    2    2    2    2    2    2    2    9            %           1259    33073    address_to_bridge    TABLE     i   CREATE TABLE citydb.address_to_bridge (
    bridge_id bigint NOT NULL,
    address_id bigint NOT NULL
);
 %   DROP TABLE citydb.address_to_bridge;
       citydb         heap    postgres    false    9            �            1259    32808    address_to_building    TABLE     m   CREATE TABLE citydb.address_to_building (
    building_id bigint NOT NULL,
    address_id bigint NOT NULL
);
 '   DROP TABLE citydb.address_to_building;
       citydb         heap    postgres    false    9            3           1259    33168    ade_seq    SEQUENCE     w   CREATE SEQUENCE citydb.ade_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;
    DROP SEQUENCE citydb.ade_seq;
       citydb          postgres    false    9            7           1259    33566    ade    TABLE     �  CREATE TABLE citydb.ade (
    id integer DEFAULT nextval('citydb.ade_seq'::regclass) NOT NULL,
    adeid character varying(256) NOT NULL,
    name character varying(1000) NOT NULL,
    description character varying(4000),
    version character varying(50),
    db_prefix character varying(10) NOT NULL,
    xml_schemamapping_file text,
    drop_db_script text,
    creation_date timestamp with time zone,
    creation_person character varying(256)
);
    DROP TABLE citydb.ade;
       citydb         heap    postgres    false    307    9            8           1259    33575    aggregation_info    TABLE     �   CREATE TABLE citydb.aggregation_info (
    child_id integer NOT NULL,
    parent_id integer NOT NULL,
    join_table_or_column_name character varying(30) NOT NULL,
    min_occurs integer,
    max_occurs integer,
    is_composite numeric
);
 $   DROP TABLE citydb.aggregation_info;
       citydb         heap    postgres    false    9                       1259    32867    appear_to_surface_data    TABLE     w   CREATE TABLE citydb.appear_to_surface_data (
    surface_data_id bigint NOT NULL,
    appearance_id bigint NOT NULL
);
 *   DROP TABLE citydb.appear_to_surface_data;
       citydb         heap    postgres    false    9                       1259    32858    appearance_seq    SEQUENCE     v   CREATE SEQUENCE citydb.appearance_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE citydb.appearance_seq;
       citydb          postgres    false    9            (           1259    33087 
   appearance    TABLE     �  CREATE TABLE citydb.appearance (
    id bigint DEFAULT nextval('citydb.appearance_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    theme character varying(256),
    citymodel_id bigint,
    cityobject_id bigint
);
    DROP TABLE citydb.appearance;
       citydb         heap    postgres    false    258    9                       1259    32872    breakline_relief    TABLE     �   CREATE TABLE citydb.breakline_relief (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    ridge_or_valley_lines public.geometry(MultiLineStringZ,32748),
    break_lines public.geometry(MultiLineStringZ,32748)
);
 $   DROP TABLE citydb.breakline_relief;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    33021    bridge    TABLE     �  CREATE TABLE citydb.bridge (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    bridge_parent_id bigint,
    bridge_root_id bigint,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    is_movable numeric,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_multi_curve public.geometry(MultiLineStringZ,32748),
    lod3_multi_curve public.geometry(MultiLineStringZ,32748),
    lod4_multi_curve public.geometry(MultiLineStringZ,32748),
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod1_solid_id bigint,
    lod2_solid_id bigint,
    lod3_solid_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.bridge;
       citydb         heap    postgres    false    9    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            $           1259    33066    bridge_constr_element    TABLE     &  CREATE TABLE citydb.bridge_constr_element (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id bigint,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod1_brep_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod1_other_geom public.geometry(GeometryZ,32748),
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod1_implicit_rep_id bigint,
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod1_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 )   DROP TABLE citydb.bridge_constr_element;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    33028    bridge_furniture    TABLE     [  CREATE TABLE citydb.bridge_furniture (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_room_id bigint,
    lod4_brep_id bigint,
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod4_implicit_rep_id bigint,
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_transformation character varying(1000)
);
 $   DROP TABLE citydb.bridge_furniture;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    33035    bridge_installation    TABLE     >  CREATE TABLE citydb.bridge_installation (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id bigint,
    bridge_room_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 '   DROP TABLE citydb.bridge_installation;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9            !           1259    33049    bridge_open_to_them_srf    TABLE     �   CREATE TABLE citydb.bridge_open_to_them_srf (
    bridge_opening_id bigint NOT NULL,
    bridge_thematic_surface_id bigint NOT NULL
);
 +   DROP TABLE citydb.bridge_open_to_them_srf;
       citydb         heap    postgres    false    9                        1259    33042    bridge_opening    TABLE     �  CREATE TABLE citydb.bridge_opening (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    address_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 "   DROP TABLE citydb.bridge_opening;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9            "           1259    33054    bridge_room    TABLE     �  CREATE TABLE citydb.bridge_room (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    bridge_id bigint,
    lod4_multi_surface_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.bridge_room;
       citydb         heap    postgres    false    9            #           1259    33061    bridge_thematic_surface    TABLE     L  CREATE TABLE citydb.bridge_thematic_surface (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    bridge_id bigint,
    bridge_room_id bigint,
    bridge_installation_id bigint,
    bridge_constr_element_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint
);
 +   DROP TABLE citydb.bridge_thematic_surface;
       citydb         heap    postgres    false    9            �            1259    32813    building    TABLE     �  CREATE TABLE citydb.building (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    building_parent_id bigint,
    building_root_id bigint,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    roof_type character varying(256),
    roof_type_codespace character varying(4000),
    measured_height double precision,
    measured_height_unit character varying(4000),
    storeys_above_ground numeric(8,0),
    storeys_below_ground numeric(8,0),
    storey_heights_above_ground character varying(4000),
    storey_heights_ag_unit character varying(4000),
    storey_heights_below_ground character varying(4000),
    storey_heights_bg_unit character varying(4000),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_multi_curve public.geometry(MultiLineStringZ,32748),
    lod3_multi_curve public.geometry(MultiLineStringZ,32748),
    lod4_multi_curve public.geometry(MultiLineStringZ,32748),
    lod0_footprint_id bigint,
    lod0_roofprint_id bigint,
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod1_solid_id bigint,
    lod2_solid_id bigint,
    lod3_solid_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.building;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2            �            1259    32820    building_furniture    TABLE     V  CREATE TABLE citydb.building_furniture (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    room_id bigint,
    lod4_brep_id bigint,
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod4_implicit_rep_id bigint,
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_transformation character varying(1000)
);
 &   DROP TABLE citydb.building_furniture;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2            �            1259    32827    building_installation    TABLE     ;  CREATE TABLE citydb.building_installation (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    building_id bigint,
    room_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 )   DROP TABLE citydb.building_installation;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9            �            1259    32792    city_furniture    TABLE     	  CREATE TABLE citydb.city_furniture (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod1_brep_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod1_other_geom public.geometry(GeometryZ,32748),
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod1_implicit_rep_id bigint,
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod1_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 "   DROP TABLE citydb.city_furniture;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9            �            1259    32751    citymodel_seq    SEQUENCE     u   CREATE SEQUENCE citydb.citymodel_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE citydb.citymodel_seq;
       citydb          postgres    false    9            -           1259    33127 	   citymodel    TABLE     o  CREATE TABLE citydb.citymodel (
    id bigint DEFAULT nextval('citydb.citymodel_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    envelope public.geometry(PolygonZ,32748),
    creation_date timestamp with time zone,
    termination_date timestamp with time zone,
    last_modification_date timestamp with time zone,
    updating_person character varying(256),
    reason_for_update character varying(4000),
    lineage character varying(256)
);
    DROP TABLE citydb.citymodel;
       citydb         heap    postgres    false    235    2    2    2    2    2    2    2    2    9            �            1259    32752    cityobject_seq    SEQUENCE     v   CREATE SEQUENCE citydb.cityobject_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 %   DROP SEQUENCE citydb.cityobject_seq;
       citydb          postgres    false    9            '           1259    33079 
   cityobject    TABLE     	  CREATE TABLE citydb.cityobject (
    id bigint DEFAULT nextval('citydb.cityobject_seq'::regclass) NOT NULL,
    objectclass_id integer NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    envelope public.geometry(PolygonZ,32748),
    creation_date timestamp with time zone,
    termination_date timestamp with time zone,
    relative_to_terrain character varying(256),
    relative_to_water character varying(256),
    last_modification_date timestamp with time zone,
    updating_person character varying(256),
    reason_for_update character varying(4000),
    lineage character varying(256),
    xml_source text
);
    DROP TABLE citydb.cityobject;
       citydb         heap    postgres    false    236    2    2    2    2    2    2    2    2    9            �            1259    32799    cityobject_genericatt_seq    SEQUENCE     �   CREATE SEQUENCE citydb.cityobject_genericatt_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 0   DROP SEQUENCE citydb.cityobject_genericatt_seq;
       citydb          postgres    false    9            .           1259    33135    cityobject_genericattrib    TABLE     z  CREATE TABLE citydb.cityobject_genericattrib (
    id bigint DEFAULT nextval('citydb.cityobject_genericatt_seq'::regclass) NOT NULL,
    parent_genattrib_id bigint,
    root_genattrib_id bigint,
    attrname character varying(256) NOT NULL,
    datatype integer,
    strval character varying(4000),
    intval integer,
    realval double precision,
    urival character varying(4000),
    dateval timestamp with time zone,
    unit character varying(4000),
    genattribset_codespace character varying(4000),
    blobval bytea,
    geomval public.geometry(GeometryZ,32748),
    surface_geometry_id bigint,
    cityobject_id bigint
);
 ,   DROP TABLE citydb.cityobject_genericattrib;
       citydb         heap    postgres    false    247    2    2    2    2    2    2    2    2    9            �            1259    32753    cityobject_member    TABLE     o   CREATE TABLE citydb.cityobject_member (
    citymodel_id bigint NOT NULL,
    cityobject_id bigint NOT NULL
);
 %   DROP TABLE citydb.cityobject_member;
       citydb         heap    postgres    false    9            �            1259    32765    cityobjectgroup    TABLE     �  CREATE TABLE citydb.cityobjectgroup (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    brep_id bigint,
    other_geom public.geometry(GeometryZ,32748),
    parent_cityobject_id bigint
);
 #   DROP TABLE citydb.cityobjectgroup;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9            �            1259    32777    database_srs    TABLE     j   CREATE TABLE citydb.database_srs (
    srid integer NOT NULL,
    gml_srs_name character varying(1000)
);
     DROP TABLE citydb.database_srs;
       citydb         heap    postgres    false    9            �            1259    32758    external_ref_seq    SEQUENCE     x   CREATE SEQUENCE citydb.external_ref_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE citydb.external_ref_seq;
       citydb          postgres    false    9            /           1259    33143    external_reference    TABLE     �   CREATE TABLE citydb.external_reference (
    id bigint DEFAULT nextval('citydb.external_ref_seq'::regclass) NOT NULL,
    infosys character varying(4000),
    name character varying(4000),
    uri character varying(4000),
    cityobject_id bigint
);
 &   DROP TABLE citydb.external_reference;
       citydb         heap    postgres    false    238    9            �            1259    32759    generalization    TABLE     q   CREATE TABLE citydb.generalization (
    cityobject_id bigint NOT NULL,
    generalizes_to_id bigint NOT NULL
);
 "   DROP TABLE citydb.generalization;
       citydb         heap    postgres    false    9            �            1259    32800    generic_cityobject    TABLE     9  CREATE TABLE citydb.generic_cityobject (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod0_brep_id bigint,
    lod1_brep_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod0_other_geom public.geometry(GeometryZ,32748),
    lod1_other_geom public.geometry(GeometryZ,32748),
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod0_implicit_rep_id bigint,
    lod1_implicit_rep_id bigint,
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod0_implicit_ref_point public.geometry(PointZ,32748),
    lod1_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod0_implicit_transformation character varying(1000),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 &   DROP TABLE citydb.generic_cityobject;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            &           1259    33078    grid_coverage_seq    SEQUENCE     y   CREATE SEQUENCE citydb.grid_coverage_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE citydb.grid_coverage_seq;
       citydb          postgres    false    9            1           1259    33159    grid_coverage    TABLE     �   CREATE TABLE citydb.grid_coverage (
    id bigint DEFAULT nextval('citydb.grid_coverage_seq'::regclass) NOT NULL,
    rasterproperty public.raster
);
 !   DROP TABLE citydb.grid_coverage;
       citydb         heap    postgres    false    294    3    3    3    9            �            1259    32772    group_to_cityobject    TABLE     �   CREATE TABLE citydb.group_to_cityobject (
    cityobject_id bigint NOT NULL,
    cityobjectgroup_id bigint NOT NULL,
    role character varying(256)
);
 '   DROP TABLE citydb.group_to_cityobject;
       citydb         heap    postgres    false    9            �            1259    32791    implicit_geometry_seq    SEQUENCE     }   CREATE SEQUENCE citydb.implicit_geometry_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 ,   DROP SEQUENCE citydb.implicit_geometry_seq;
       citydb          postgres    false    9            )           1259    33095    implicit_geometry    TABLE     �  CREATE TABLE citydb.implicit_geometry (
    id bigint DEFAULT nextval('citydb.implicit_geometry_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    mime_type character varying(256),
    reference_to_library character varying(4000),
    library_object bytea,
    relative_brep_id bigint,
    relative_other_geom public.geometry(GeometryZ)
);
 %   DROP TABLE citydb.implicit_geometry;
       citydb         heap    postgres    false    245    9    2    2    2    2    2    2    2    2            ;           1259    35244    index_table    TABLE     [   CREATE TABLE citydb.index_table (
    id integer NOT NULL,
    obj citydb_pkg.index_obj
);
    DROP TABLE citydb.index_table;
       citydb         heap    postgres    false    2677    9            :           1259    35243    index_table_id_seq    SEQUENCE     �   CREATE SEQUENCE citydb.index_table_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE citydb.index_table_id_seq;
       citydb          postgres    false    315    9                       0    0    index_table_id_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE citydb.index_table_id_seq OWNED BY citydb.index_table.id;
          citydb          postgres    false    314                       1259    32928    land_use    TABLE     �  CREATE TABLE citydb.land_use (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_multi_surface_id bigint,
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint
);
    DROP TABLE citydb.land_use;
       citydb         heap    postgres    false    9                       1259    32879    masspoint_relief    TABLE     �   CREATE TABLE citydb.masspoint_relief (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    relief_points public.geometry(MultiPointZ,32748)
);
 $   DROP TABLE citydb.masspoint_relief;
       citydb         heap    postgres    false    9    2    2    2    2    2    2    2    2            �            1259    32784    objectclass    TABLE       CREATE TABLE citydb.objectclass (
    id integer NOT NULL,
    is_ade_class numeric,
    is_toplevel numeric,
    classname character varying(256),
    tablename character varying(30),
    superclass_id integer,
    baseclass_id integer,
    ade_id integer
);
    DROP TABLE citydb.objectclass;
       citydb         heap    postgres    false    9            �            1259    32834    opening    TABLE     �  CREATE TABLE citydb.opening (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    address_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
    DROP TABLE citydb.opening;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2            �            1259    32841    opening_to_them_surface    TABLE     y   CREATE TABLE citydb.opening_to_them_surface (
    opening_id bigint NOT NULL,
    thematic_surface_id bigint NOT NULL
);
 +   DROP TABLE citydb.opening_to_them_surface;
       citydb         heap    postgres    false    9                       1259    32935    plant_cover    TABLE     �  CREATE TABLE citydb.plant_cover (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    average_height double precision,
    average_height_unit character varying(4000),
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod1_multi_solid_id bigint,
    lod2_multi_solid_id bigint,
    lod3_multi_solid_id bigint,
    lod4_multi_solid_id bigint
);
    DROP TABLE citydb.plant_cover;
       citydb         heap    postgres    false    9                       1259    32968    raster_relief    TABLE     �   CREATE TABLE citydb.raster_relief (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    raster_uri character varying(4000),
    coverage_id bigint
);
 !   DROP TABLE citydb.raster_relief;
       citydb         heap    postgres    false    9                       1259    32886    relief_component    TABLE     �   CREATE TABLE citydb.relief_component (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    lod numeric,
    extent public.geometry(Polygon,32748),
    CONSTRAINT relief_comp_lod_chk CHECK (((lod >= (0)::numeric) AND (lod < (5)::numeric)))
);
 $   DROP TABLE citydb.relief_component;
       citydb         heap    postgres    false    9    2    2    2    2    2    2    2    2            	           1259    32894    relief_feat_to_rel_comp    TABLE     �   CREATE TABLE citydb.relief_feat_to_rel_comp (
    relief_component_id bigint NOT NULL,
    relief_feature_id bigint NOT NULL
);
 +   DROP TABLE citydb.relief_feat_to_rel_comp;
       citydb         heap    postgres    false    9            
           1259    32899    relief_feature    TABLE     �   CREATE TABLE citydb.relief_feature (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    lod numeric,
    CONSTRAINT relief_feat_lod_chk CHECK (((lod >= (0)::numeric) AND (lod < (5)::numeric)))
);
 "   DROP TABLE citydb.relief_feature;
       citydb         heap    postgres    false    9                        1259    32846    room    TABLE     �  CREATE TABLE citydb.room (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    building_id bigint,
    lod4_multi_surface_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.room;
       citydb         heap    postgres    false    9            2           1259    33167 
   schema_seq    SEQUENCE     z   CREATE SEQUENCE citydb.schema_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    MAXVALUE 2147483647
    CACHE 1;
 !   DROP SEQUENCE citydb.schema_seq;
       citydb          postgres    false    9            4           1259    33521    schema    TABLE     �  CREATE TABLE citydb.schema (
    id integer DEFAULT nextval('citydb.schema_seq'::regclass) NOT NULL,
    is_ade_root numeric NOT NULL,
    citygml_version character varying(50) NOT NULL,
    xml_namespace_uri character varying(4000) NOT NULL,
    xml_namespace_prefix character varying(50) NOT NULL,
    xml_schema_location character varying(4000),
    xml_schemafile bytea,
    xml_schemafile_type character varying(256),
    ade_id integer
);
    DROP TABLE citydb.schema;
       citydb         heap    postgres    false    306    9            6           1259    33537    schema_referencing    TABLE     t   CREATE TABLE citydb.schema_referencing (
    referencing_id integer NOT NULL,
    referenced_id integer NOT NULL
);
 &   DROP TABLE citydb.schema_referencing;
       citydb         heap    postgres    false    9            5           1259    33529    schema_to_objectclass    TABLE     s   CREATE TABLE citydb.schema_to_objectclass (
    schema_id integer NOT NULL,
    objectclass_id integer NOT NULL
);
 )   DROP TABLE citydb.schema_to_objectclass;
       citydb         heap    postgres    false    9                       1259    32942    solitary_vegetat_object    TABLE     <  CREATE TABLE citydb.solitary_vegetat_object (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    species character varying(1000),
    species_codespace character varying(4000),
    height double precision,
    height_unit character varying(4000),
    trunk_diameter double precision,
    trunk_diameter_unit character varying(4000),
    crown_diameter double precision,
    crown_diameter_unit character varying(4000),
    lod1_brep_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod1_other_geom public.geometry(GeometryZ,32748),
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod1_implicit_rep_id bigint,
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod1_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod1_implicit_transformation character varying(1000),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 +   DROP TABLE citydb.solitary_vegetat_object;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    32859    surface_data_seq    SEQUENCE     x   CREATE SEQUENCE citydb.surface_data_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE citydb.surface_data_seq;
       citydb          postgres    false    9            ,           1259    33119    surface_data    TABLE     �  CREATE TABLE citydb.surface_data (
    id bigint DEFAULT nextval('citydb.surface_data_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    name character varying(1000),
    name_codespace character varying(4000),
    description character varying(4000),
    is_front numeric,
    objectclass_id integer NOT NULL,
    x3d_shininess double precision,
    x3d_transparency double precision,
    x3d_ambient_intensity double precision,
    x3d_specular_color character varying(256),
    x3d_diffuse_color character varying(256),
    x3d_emissive_color character varying(256),
    x3d_is_smooth numeric,
    tex_image_id bigint,
    tex_texture_type character varying(256),
    tex_wrap_mode character varying(256),
    tex_border_color character varying(256),
    gt_prefer_worldfile numeric,
    gt_orientation character varying(256),
    gt_reference_point public.geometry(Point,32748)
);
     DROP TABLE citydb.surface_data;
       citydb         heap    postgres    false    259    9    2    2    2    2    2    2    2    2            �            1259    32764    surface_geometry_seq    SEQUENCE     |   CREATE SEQUENCE citydb.surface_geometry_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE citydb.surface_geometry_seq;
       citydb          postgres    false    9            *           1259    33103    surface_geometry    TABLE     %  CREATE TABLE citydb.surface_geometry (
    id bigint DEFAULT nextval('citydb.surface_geometry_seq'::regclass) NOT NULL,
    gmlid character varying(256),
    gmlid_codespace character varying(1000),
    parent_id bigint,
    root_id bigint,
    is_solid numeric,
    is_composite numeric,
    is_triangulated numeric,
    is_xlink numeric,
    is_reverse numeric,
    solid_geometry public.geometry(PolyhedralSurfaceZ,32748),
    geometry public.geometry(PolygonZ,32748),
    implicit_geometry public.geometry(PolygonZ),
    cityobject_id bigint
);
 $   DROP TABLE citydb.surface_geometry;
       citydb         heap    postgres    false    240    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2                       1259    32999    tex_image_seq    SEQUENCE     u   CREATE SEQUENCE citydb.tex_image_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 0
    NO MAXVALUE
    CACHE 1;
 $   DROP SEQUENCE citydb.tex_image_seq;
       citydb          postgres    false    9            0           1259    33151 	   tex_image    TABLE       CREATE TABLE citydb.tex_image (
    id bigint DEFAULT nextval('citydb.tex_image_seq'::regclass) NOT NULL,
    tex_image_uri character varying(4000),
    tex_image_data bytea,
    tex_mime_type character varying(256),
    tex_mime_type_codespace character varying(4000)
);
    DROP TABLE citydb.tex_image;
       citydb         heap    postgres    false    281    9                       1259    32860    textureparam    TABLE     �   CREATE TABLE citydb.textureparam (
    surface_geometry_id bigint NOT NULL,
    is_texture_parametrization numeric,
    world_to_texture character varying(1000),
    texture_coordinates public.geometry(Polygon),
    surface_data_id bigint NOT NULL
);
     DROP TABLE citydb.textureparam;
       citydb         heap    postgres    false    9    2    2    2    2    2    2    2    2                       1259    32853    thematic_surface    TABLE       CREATE TABLE citydb.thematic_surface (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    building_id bigint,
    room_id bigint,
    building_installation_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint
);
 $   DROP TABLE citydb.thematic_surface;
       citydb         heap    postgres    false    9                       1259    32907 
   tin_relief    TABLE     v  CREATE TABLE citydb.tin_relief (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    max_length double precision,
    max_length_unit character varying(4000),
    stop_lines public.geometry(MultiLineStringZ,32748),
    break_lines public.geometry(MultiLineStringZ,32748),
    control_points public.geometry(MultiPointZ,32748),
    surface_geometry_id bigint
);
    DROP TABLE citydb.tin_relief;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    32921    traffic_area    TABLE     H  CREATE TABLE citydb.traffic_area (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    surface_material character varying(256),
    surface_material_codespace character varying(4000),
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    transportation_complex_id bigint
);
     DROP TABLE citydb.traffic_area;
       citydb         heap    postgres    false    9                       1259    32914    transportation_complex    TABLE       CREATE TABLE citydb.transportation_complex (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_network public.geometry(GeometryZ,32748),
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint
);
 *   DROP TABLE citydb.transportation_complex;
       citydb         heap    postgres    false    9    2    2    2    2    2    2    2    2                       1259    32975    tunnel    TABLE     �  CREATE TABLE citydb.tunnel (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    tunnel_parent_id bigint,
    tunnel_root_id bigint,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    year_of_construction date,
    year_of_demolition date,
    lod1_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod3_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod4_terrain_intersection public.geometry(MultiLineStringZ,32748),
    lod2_multi_curve public.geometry(MultiLineStringZ,32748),
    lod3_multi_curve public.geometry(MultiLineStringZ,32748),
    lod4_multi_curve public.geometry(MultiLineStringZ,32748),
    lod1_multi_surface_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod1_solid_id bigint,
    lod2_solid_id bigint,
    lod3_solid_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.tunnel;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    33014    tunnel_furniture    TABLE     c  CREATE TABLE citydb.tunnel_furniture (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_hollow_space_id bigint,
    lod4_brep_id bigint,
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod4_implicit_rep_id bigint,
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_transformation character varying(1000)
);
 $   DROP TABLE citydb.tunnel_furniture;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    32987    tunnel_hollow_space    TABLE     �  CREATE TABLE citydb.tunnel_hollow_space (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_id bigint,
    lod4_multi_surface_id bigint,
    lod4_solid_id bigint
);
 '   DROP TABLE citydb.tunnel_hollow_space;
       citydb         heap    postgres    false    9                       1259    33007    tunnel_installation    TABLE     F  CREATE TABLE citydb.tunnel_installation (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    tunnel_id bigint,
    tunnel_hollow_space_id bigint,
    lod2_brep_id bigint,
    lod3_brep_id bigint,
    lod4_brep_id bigint,
    lod2_other_geom public.geometry(GeometryZ,32748),
    lod3_other_geom public.geometry(GeometryZ,32748),
    lod4_other_geom public.geometry(GeometryZ,32748),
    lod2_implicit_rep_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod2_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod2_implicit_transformation character varying(1000),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 '   DROP TABLE citydb.tunnel_installation;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    32982    tunnel_open_to_them_srf    TABLE     �   CREATE TABLE citydb.tunnel_open_to_them_srf (
    tunnel_opening_id bigint NOT NULL,
    tunnel_thematic_surface_id bigint NOT NULL
);
 +   DROP TABLE citydb.tunnel_open_to_them_srf;
       citydb         heap    postgres    false    9                       1259    33000    tunnel_opening    TABLE     �  CREATE TABLE citydb.tunnel_opening (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint,
    lod3_implicit_rep_id bigint,
    lod4_implicit_rep_id bigint,
    lod3_implicit_ref_point public.geometry(PointZ,32748),
    lod4_implicit_ref_point public.geometry(PointZ,32748),
    lod3_implicit_transformation character varying(1000),
    lod4_implicit_transformation character varying(1000)
);
 "   DROP TABLE citydb.tunnel_opening;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    9    2    2    2    2    2    2    2    2                       1259    32994    tunnel_thematic_surface    TABLE     /  CREATE TABLE citydb.tunnel_thematic_surface (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    tunnel_id bigint,
    tunnel_hollow_space_id bigint,
    tunnel_installation_id bigint,
    lod2_multi_surface_id bigint,
    lod3_multi_surface_id bigint,
    lod4_multi_surface_id bigint
);
 +   DROP TABLE citydb.tunnel_thematic_surface;
       citydb         heap    postgres    false    9                       1259    32956    waterbod_to_waterbnd_srf    TABLE     �   CREATE TABLE citydb.waterbod_to_waterbnd_srf (
    waterboundary_surface_id bigint NOT NULL,
    waterbody_id bigint NOT NULL
);
 ,   DROP TABLE citydb.waterbod_to_waterbnd_srf;
       citydb         heap    postgres    false    9                       1259    32949 	   waterbody    TABLE     |  CREATE TABLE citydb.waterbody (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    class character varying(256),
    class_codespace character varying(4000),
    function character varying(1000),
    function_codespace character varying(4000),
    usage character varying(1000),
    usage_codespace character varying(4000),
    lod0_multi_curve public.geometry(MultiLineStringZ,32748),
    lod1_multi_curve public.geometry(MultiLineStringZ,32748),
    lod0_multi_surface_id bigint,
    lod1_multi_surface_id bigint,
    lod1_solid_id bigint,
    lod2_solid_id bigint,
    lod3_solid_id bigint,
    lod4_solid_id bigint
);
    DROP TABLE citydb.waterbody;
       citydb         heap    postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    9                       1259    32961    waterboundary_surface    TABLE       CREATE TABLE citydb.waterboundary_surface (
    id bigint NOT NULL,
    objectclass_id integer NOT NULL,
    water_level character varying(256),
    water_level_codespace character varying(4000),
    lod2_surface_id bigint,
    lod3_surface_id bigint,
    lod4_surface_id bigint
);
 )   DROP TABLE citydb.waterboundary_surface;
       citydb         heap    postgres    false    9            �           2604    35247    index_table id    DEFAULT     p   ALTER TABLE ONLY citydb.index_table ALTER COLUMN id SET DEFAULT nextval('citydb.index_table_id_seq'::regclass);
 =   ALTER TABLE citydb.index_table ALTER COLUMN id DROP DEFAULT;
       citydb          postgres    false    315    314    315                      0    33111    address 
   TABLE DATA           �   COPY citydb.address (id, gmlid, gmlid_codespace, street, house_number, po_box, zip_code, city, state, country, multi_point, xal_source) FROM stdin;
    citydb          postgres    false    299   u�      �          0    33073    address_to_bridge 
   TABLE DATA           B   COPY citydb.address_to_bridge (bridge_id, address_id) FROM stdin;
    citydb          postgres    false    293   ��      �          0    32808    address_to_building 
   TABLE DATA           F   COPY citydb.address_to_building (building_id, address_id) FROM stdin;
    citydb          postgres    false    250   ��                0    33566    ade 
   TABLE DATA           �   COPY citydb.ade (id, adeid, name, description, version, db_prefix, xml_schemamapping_file, drop_db_script, creation_date, creation_person) FROM stdin;
    citydb          postgres    false    311   ̄                0    33575    aggregation_info 
   TABLE DATA           �   COPY citydb.aggregation_info (child_id, parent_id, join_table_or_column_name, min_occurs, max_occurs, is_composite) FROM stdin;
    citydb          postgres    false    312   �      �          0    32867    appear_to_surface_data 
   TABLE DATA           P   COPY citydb.appear_to_surface_data (surface_data_id, appearance_id) FROM stdin;
    citydb          postgres    false    261   ��                0    33087 
   appearance 
   TABLE DATA           �   COPY citydb.appearance (id, gmlid, gmlid_codespace, name, name_codespace, description, theme, citymodel_id, cityobject_id) FROM stdin;
    citydb          postgres    false    296   �      �          0    32872    breakline_relief 
   TABLE DATA           b   COPY citydb.breakline_relief (id, objectclass_id, ridge_or_valley_lines, break_lines) FROM stdin;
    citydb          postgres    false    262   9�      �          0    33021    bridge 
   TABLE DATA             COPY citydb.bridge (id, objectclass_id, bridge_parent_id, bridge_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, is_movable, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    285   V�      �          0    33066    bridge_constr_element 
   TABLE DATA           �  COPY citydb.bridge_constr_element (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    292   s�      �          0    33028    bridge_furniture 
   TABLE DATA             COPY citydb.bridge_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_room_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    286   ��      �          0    33035    bridge_installation 
   TABLE DATA           �  COPY citydb.bridge_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, bridge_room_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    287   ��      �          0    33049    bridge_open_to_them_srf 
   TABLE DATA           `   COPY citydb.bridge_open_to_them_srf (bridge_opening_id, bridge_thematic_surface_id) FROM stdin;
    citydb          postgres    false    289   ʉ      �          0    33042    bridge_opening 
   TABLE DATA             COPY citydb.bridge_opening (id, objectclass_id, address_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    288   �      �          0    33054    bridge_room 
   TABLE DATA           �   COPY citydb.bridge_room (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, bridge_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    290   �      �          0    33061    bridge_thematic_surface 
   TABLE DATA           �   COPY citydb.bridge_thematic_surface (id, objectclass_id, bridge_id, bridge_room_id, bridge_installation_id, bridge_constr_element_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
    citydb          postgres    false    291   !�      �          0    32813    building 
   TABLE DATA             COPY citydb.building (id, objectclass_id, building_parent_id, building_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, roof_type, roof_type_codespace, measured_height, measured_height_unit, storeys_above_ground, storeys_below_ground, storey_heights_above_ground, storey_heights_ag_unit, storey_heights_below_ground, storey_heights_bg_unit, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod0_footprint_id, lod0_roofprint_id, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    251   >�      �          0    32820    building_furniture 
   TABLE DATA             COPY citydb.building_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, room_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    252   [�      �          0    32827    building_installation 
   TABLE DATA           �  COPY citydb.building_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, building_id, room_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    253   x�      �          0    32792    city_furniture 
   TABLE DATA           �  COPY citydb.city_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    246   ��                0    33127 	   citymodel 
   TABLE DATA           �   COPY citydb.citymodel (id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, last_modification_date, updating_person, reason_for_update, lineage) FROM stdin;
    citydb          postgres    false    301   ��                 0    33079 
   cityobject 
   TABLE DATA             COPY citydb.cityobject (id, objectclass_id, gmlid, gmlid_codespace, name, name_codespace, description, envelope, creation_date, termination_date, relative_to_terrain, relative_to_water, last_modification_date, updating_person, reason_for_update, lineage, xml_source) FROM stdin;
    citydb          postgres    false    295   ϊ                0    33135    cityobject_genericattrib 
   TABLE DATA           �   COPY citydb.cityobject_genericattrib (id, parent_genattrib_id, root_genattrib_id, attrname, datatype, strval, intval, realval, urival, dateval, unit, genattribset_codespace, blobval, geomval, surface_geometry_id, cityobject_id) FROM stdin;
    citydb          postgres    false    302   �      �          0    32753    cityobject_member 
   TABLE DATA           H   COPY citydb.cityobject_member (citymodel_id, cityobject_id) FROM stdin;
    citydb          postgres    false    237   	�      �          0    32765    cityobjectgroup 
   TABLE DATA           �   COPY citydb.cityobjectgroup (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, brep_id, other_geom, parent_cityobject_id) FROM stdin;
    citydb          postgres    false    241   &�      �          0    32777    database_srs 
   TABLE DATA           :   COPY citydb.database_srs (srid, gml_srs_name) FROM stdin;
    citydb          postgres    false    243   C�                0    33143    external_reference 
   TABLE DATA           S   COPY citydb.external_reference (id, infosys, name, uri, cityobject_id) FROM stdin;
    citydb          postgres    false    303   ��      �          0    32759    generalization 
   TABLE DATA           J   COPY citydb.generalization (cityobject_id, generalizes_to_id) FROM stdin;
    citydb          postgres    false    239   ��      �          0    32800    generic_cityobject 
   TABLE DATA           1  COPY citydb.generic_cityobject (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_terrain_intersection, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod0_brep_id, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod0_other_geom, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod0_implicit_rep_id, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod0_implicit_ref_point, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod0_implicit_transformation, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    248   ��      
          0    33159    grid_coverage 
   TABLE DATA           ;   COPY citydb.grid_coverage (id, rasterproperty) FROM stdin;
    citydb          postgres    false    305   ׋      �          0    32772    group_to_cityobject 
   TABLE DATA           V   COPY citydb.group_to_cityobject (cityobject_id, cityobjectgroup_id, role) FROM stdin;
    citydb          postgres    false    242   �                0    33095    implicit_geometry 
   TABLE DATA           �   COPY citydb.implicit_geometry (id, gmlid, gmlid_codespace, mime_type, reference_to_library, library_object, relative_brep_id, relative_other_geom) FROM stdin;
    citydb          postgres    false    297   �                0    35244    index_table 
   TABLE DATA           .   COPY citydb.index_table (id, obj) FROM stdin;
    citydb          postgres    false    315   .�      �          0    32928    land_use 
   TABLE DATA           �   COPY citydb.land_use (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_multi_surface_id, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
    citydb          postgres    false    270   2�      �          0    32879    masspoint_relief 
   TABLE DATA           M   COPY citydb.masspoint_relief (id, objectclass_id, relief_points) FROM stdin;
    citydb          postgres    false    263   O�      �          0    32784    objectclass 
   TABLE DATA              COPY citydb.objectclass (id, is_ade_class, is_toplevel, classname, tablename, superclass_id, baseclass_id, ade_id) FROM stdin;
    citydb          postgres    false    244   l�      �          0    32834    opening 
   TABLE DATA           	  COPY citydb.opening (id, objectclass_id, address_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    254   ڒ      �          0    32841    opening_to_them_surface 
   TABLE DATA           R   COPY citydb.opening_to_them_surface (opening_id, thematic_surface_id) FROM stdin;
    citydb          postgres    false    255   ��      �          0    32935    plant_cover 
   TABLE DATA           \  COPY citydb.plant_cover (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, average_height, average_height_unit, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_multi_solid_id, lod2_multi_solid_id, lod3_multi_solid_id, lod4_multi_solid_id) FROM stdin;
    citydb          postgres    false    271   �      �          0    32968    raster_relief 
   TABLE DATA           T   COPY citydb.raster_relief (id, objectclass_id, raster_uri, coverage_id) FROM stdin;
    citydb          postgres    false    276   1�      �          0    32886    relief_component 
   TABLE DATA           K   COPY citydb.relief_component (id, objectclass_id, lod, extent) FROM stdin;
    citydb          postgres    false    264   N�      �          0    32894    relief_feat_to_rel_comp 
   TABLE DATA           Y   COPY citydb.relief_feat_to_rel_comp (relief_component_id, relief_feature_id) FROM stdin;
    citydb          postgres    false    265   k�      �          0    32899    relief_feature 
   TABLE DATA           A   COPY citydb.relief_feature (id, objectclass_id, lod) FROM stdin;
    citydb          postgres    false    266   ��      �          0    32846    room 
   TABLE DATA           �   COPY citydb.room (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, building_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    256   ��                0    33521    schema 
   TABLE DATA           �   COPY citydb.schema (id, is_ade_root, citygml_version, xml_namespace_uri, xml_namespace_prefix, xml_schema_location, xml_schemafile, xml_schemafile_type, ade_id) FROM stdin;
    citydb          postgres    false    308                   0    33537    schema_referencing 
   TABLE DATA           K   COPY citydb.schema_referencing (referencing_id, referenced_id) FROM stdin;
    citydb          postgres    false    310   ߓ                0    33529    schema_to_objectclass 
   TABLE DATA           J   COPY citydb.schema_to_objectclass (schema_id, objectclass_id) FROM stdin;
    citydb          postgres    false    309   ��      �          0    32942    solitary_vegetat_object 
   TABLE DATA           �  COPY citydb.solitary_vegetat_object (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, species, species_codespace, height, height_unit, trunk_diameter, trunk_diameter_unit, crown_diameter, crown_diameter_unit, lod1_brep_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod1_other_geom, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod1_implicit_rep_id, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod1_implicit_ref_point, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod1_implicit_transformation, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    272   �                0    33119    surface_data 
   TABLE DATA           {  COPY citydb.surface_data (id, gmlid, gmlid_codespace, name, name_codespace, description, is_front, objectclass_id, x3d_shininess, x3d_transparency, x3d_ambient_intensity, x3d_specular_color, x3d_diffuse_color, x3d_emissive_color, x3d_is_smooth, tex_image_id, tex_texture_type, tex_wrap_mode, tex_border_color, gt_prefer_worldfile, gt_orientation, gt_reference_point) FROM stdin;
    citydb          postgres    false    300   6�                0    33103    surface_geometry 
   TABLE DATA           �   COPY citydb.surface_geometry (id, gmlid, gmlid_codespace, parent_id, root_id, is_solid, is_composite, is_triangulated, is_xlink, is_reverse, solid_geometry, geometry, implicit_geometry, cityobject_id) FROM stdin;
    citydb          postgres    false    298   S�      	          0    33151 	   tex_image 
   TABLE DATA           n   COPY citydb.tex_image (id, tex_image_uri, tex_image_data, tex_mime_type, tex_mime_type_codespace) FROM stdin;
    citydb          postgres    false    304   p�      �          0    32860    textureparam 
   TABLE DATA           �   COPY citydb.textureparam (surface_geometry_id, is_texture_parametrization, world_to_texture, texture_coordinates, surface_data_id) FROM stdin;
    citydb          postgres    false    260   ��      �          0    32853    thematic_surface 
   TABLE DATA           �   COPY citydb.thematic_surface (id, objectclass_id, building_id, room_id, building_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
    citydb          postgres    false    257   ��      �          0    32907 
   tin_relief 
   TABLE DATA           �   COPY citydb.tin_relief (id, objectclass_id, max_length, max_length_unit, stop_lines, break_lines, control_points, surface_geometry_id) FROM stdin;
    citydb          postgres    false    267   ǔ      �          0    32921    traffic_area 
   TABLE DATA             COPY citydb.traffic_area (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, surface_material, surface_material_codespace, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, transportation_complex_id) FROM stdin;
    citydb          postgres    false    269   �      �          0    32914    transportation_complex 
   TABLE DATA           �   COPY citydb.transportation_complex (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_network, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
    citydb          postgres    false    268   �      �          0    32975    tunnel 
   TABLE DATA             COPY citydb.tunnel (id, objectclass_id, tunnel_parent_id, tunnel_root_id, class, class_codespace, function, function_codespace, usage, usage_codespace, year_of_construction, year_of_demolition, lod1_terrain_intersection, lod2_terrain_intersection, lod3_terrain_intersection, lod4_terrain_intersection, lod2_multi_curve, lod3_multi_curve, lod4_multi_curve, lod1_multi_surface_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    277   �      �          0    33014    tunnel_furniture 
   TABLE DATA             COPY citydb.tunnel_furniture (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_hollow_space_id, lod4_brep_id, lod4_other_geom, lod4_implicit_rep_id, lod4_implicit_ref_point, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    284   ;�      �          0    32987    tunnel_hollow_space 
   TABLE DATA           �   COPY citydb.tunnel_hollow_space (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_id, lod4_multi_surface_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    279   X�      �          0    33007    tunnel_installation 
   TABLE DATA           �  COPY citydb.tunnel_installation (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, tunnel_id, tunnel_hollow_space_id, lod2_brep_id, lod3_brep_id, lod4_brep_id, lod2_other_geom, lod3_other_geom, lod4_other_geom, lod2_implicit_rep_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod2_implicit_ref_point, lod3_implicit_ref_point, lod4_implicit_ref_point, lod2_implicit_transformation, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    283   u�      �          0    32982    tunnel_open_to_them_srf 
   TABLE DATA           `   COPY citydb.tunnel_open_to_them_srf (tunnel_opening_id, tunnel_thematic_surface_id) FROM stdin;
    citydb          postgres    false    278   ��      �          0    33000    tunnel_opening 
   TABLE DATA             COPY citydb.tunnel_opening (id, objectclass_id, lod3_multi_surface_id, lod4_multi_surface_id, lod3_implicit_rep_id, lod4_implicit_rep_id, lod3_implicit_ref_point, lod4_implicit_ref_point, lod3_implicit_transformation, lod4_implicit_transformation) FROM stdin;
    citydb          postgres    false    282   ��      �          0    32994    tunnel_thematic_surface 
   TABLE DATA           �   COPY citydb.tunnel_thematic_surface (id, objectclass_id, tunnel_id, tunnel_hollow_space_id, tunnel_installation_id, lod2_multi_surface_id, lod3_multi_surface_id, lod4_multi_surface_id) FROM stdin;
    citydb          postgres    false    280   ̕      �          0    32956    waterbod_to_waterbnd_srf 
   TABLE DATA           Z   COPY citydb.waterbod_to_waterbnd_srf (waterboundary_surface_id, waterbody_id) FROM stdin;
    citydb          postgres    false    274   �      �          0    32949 	   waterbody 
   TABLE DATA             COPY citydb.waterbody (id, objectclass_id, class, class_codespace, function, function_codespace, usage, usage_codespace, lod0_multi_curve, lod1_multi_curve, lod0_multi_surface_id, lod1_multi_surface_id, lod1_solid_id, lod2_solid_id, lod3_solid_id, lod4_solid_id) FROM stdin;
    citydb          postgres    false    273   �      �          0    32961    waterboundary_surface 
   TABLE DATA           �   COPY citydb.waterboundary_surface (id, objectclass_id, water_level, water_level_codespace, lod2_surface_id, lod3_surface_id, lod4_surface_id) FROM stdin;
    citydb          postgres    false    275   #�      �          0    31365    spatial_ref_sys 
   TABLE DATA           X   COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
    public          postgres    false    221   @�                 0    0    address_seq    SEQUENCE SET     :   SELECT pg_catalog.setval('citydb.address_seq', 1, false);
          citydb          postgres    false    249                        0    0    ade_seq    SEQUENCE SET     6   SELECT pg_catalog.setval('citydb.ade_seq', 1, false);
          citydb          postgres    false    307            !           0    0    appearance_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('citydb.appearance_seq', 1, false);
          citydb          postgres    false    258            "           0    0    citymodel_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('citydb.citymodel_seq', 1, false);
          citydb          postgres    false    235            #           0    0    cityobject_genericatt_seq    SEQUENCE SET     H   SELECT pg_catalog.setval('citydb.cityobject_genericatt_seq', 1, false);
          citydb          postgres    false    247            $           0    0    cityobject_seq    SEQUENCE SET     =   SELECT pg_catalog.setval('citydb.cityobject_seq', 1, false);
          citydb          postgres    false    236            %           0    0    external_ref_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('citydb.external_ref_seq', 1, false);
          citydb          postgres    false    238            &           0    0    grid_coverage_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('citydb.grid_coverage_seq', 1, false);
          citydb          postgres    false    294            '           0    0    implicit_geometry_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('citydb.implicit_geometry_seq', 1, false);
          citydb          postgres    false    245            (           0    0    index_table_id_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('citydb.index_table_id_seq', 13, true);
          citydb          postgres    false    314            )           0    0 
   schema_seq    SEQUENCE SET     9   SELECT pg_catalog.setval('citydb.schema_seq', 1, false);
          citydb          postgres    false    306            *           0    0    surface_data_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('citydb.surface_data_seq', 1, false);
          citydb          postgres    false    259            +           0    0    surface_geometry_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('citydb.surface_geometry_seq', 1, false);
          citydb          postgres    false    240            ,           0    0    tex_image_seq    SEQUENCE SET     <   SELECT pg_catalog.setval('citydb.tex_image_seq', 1, false);
          citydb          postgres    false    281            �           2606    33118    address address_pk 
   CONSTRAINT     h   ALTER TABLE ONLY citydb.address
    ADD CONSTRAINT address_pk PRIMARY KEY (id) WITH (fillfactor='100');
 <   ALTER TABLE ONLY citydb.address DROP CONSTRAINT address_pk;
       citydb            postgres    false    299            �           2606    33077 &   address_to_bridge address_to_bridge_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_pk PRIMARY KEY (bridge_id, address_id) WITH (fillfactor='100');
 P   ALTER TABLE ONLY citydb.address_to_bridge DROP CONSTRAINT address_to_bridge_pk;
       citydb            postgres    false    293    293            R           2606    32812 *   address_to_building address_to_building_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_pk PRIMARY KEY (building_id, address_id) WITH (fillfactor='100');
 T   ALTER TABLE ONLY citydb.address_to_building DROP CONSTRAINT address_to_building_pk;
       citydb            postgres    false    250    250                       2606    33573 
   ade ade_pk 
   CONSTRAINT     `   ALTER TABLE ONLY citydb.ade
    ADD CONSTRAINT ade_pk PRIMARY KEY (id) WITH (fillfactor='100');
 4   ALTER TABLE ONLY citydb.ade DROP CONSTRAINT ade_pk;
       citydb            postgres    false    311                       2606    33581 $   aggregation_info aggregation_info_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_pk PRIMARY KEY (child_id, parent_id, join_table_or_column_name);
 N   ALTER TABLE ONLY citydb.aggregation_info DROP CONSTRAINT aggregation_info_pk;
       citydb            postgres    false    312    312    312            �           2606    32871 0   appear_to_surface_data appear_to_surface_data_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT appear_to_surface_data_pk PRIMARY KEY (surface_data_id, appearance_id) WITH (fillfactor='100');
 Z   ALTER TABLE ONLY citydb.appear_to_surface_data DROP CONSTRAINT appear_to_surface_data_pk;
       citydb            postgres    false    261    261            �           2606    33094    appearance appearance_pk 
   CONSTRAINT     n   ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_pk PRIMARY KEY (id) WITH (fillfactor='100');
 B   ALTER TABLE ONLY citydb.appearance DROP CONSTRAINT appearance_pk;
       citydb            postgres    false    296            �           2606    32878 $   breakline_relief breakline_relief_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.breakline_relief DROP CONSTRAINT breakline_relief_pk;
       citydb            postgres    false    262            �           2606    33072 .   bridge_constr_element bridge_constr_element_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_element_pk PRIMARY KEY (id) WITH (fillfactor='100');
 X   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_element_pk;
       citydb            postgres    false    292            t           2606    33034 $   bridge_furniture bridge_furniture_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furniture_pk;
       citydb            postgres    false    286            �           2606    33041 *   bridge_installation bridge_installation_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');
 T   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_installation_pk;
       citydb            postgres    false    287            �           2606    33053 2   bridge_open_to_them_srf bridge_open_to_them_srf_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT bridge_open_to_them_srf_pk PRIMARY KEY (bridge_opening_id, bridge_thematic_surface_id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.bridge_open_to_them_srf DROP CONSTRAINT bridge_open_to_them_srf_pk;
       citydb            postgres    false    289    289            �           2606    33048     bridge_opening bridge_opening_pk 
   CONSTRAINT     v   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');
 J   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_opening_pk;
       citydb            postgres    false    288            k           2606    33027    bridge bridge_pk 
   CONSTRAINT     f   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_pk PRIMARY KEY (id) WITH (fillfactor='100');
 :   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_pk;
       citydb            postgres    false    285            �           2606    33060    bridge_room bridge_room_pk 
   CONSTRAINT     p   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_pk PRIMARY KEY (id) WITH (fillfactor='100');
 D   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_pk;
       citydb            postgres    false    290            �           2606    33065 2   bridge_thematic_surface bridge_thematic_surface_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT bridge_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT bridge_thematic_surface_pk;
       citydb            postgres    false    291            p           2606    32826 (   building_furniture building_furniture_pk 
   CONSTRAINT     ~   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT building_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');
 R   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT building_furniture_pk;
       citydb            postgres    false    252            �           2606    32833 .   building_installation building_installation_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT building_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');
 X   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT building_installation_pk;
       citydb            postgres    false    253            g           2606    32819    building building_pk 
   CONSTRAINT     j   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_pk PRIMARY KEY (id) WITH (fillfactor='100');
 >   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_pk;
       citydb            postgres    false    251            2           2606    32798     city_furniture city_furniture_pk 
   CONSTRAINT     v   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');
 J   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furniture_pk;
       citydb            postgres    false    246            �           2606    33134    citymodel citymodel_pk 
   CONSTRAINT     l   ALTER TABLE ONLY citydb.citymodel
    ADD CONSTRAINT citymodel_pk PRIMARY KEY (id) WITH (fillfactor='100');
 @   ALTER TABLE ONLY citydb.citymodel DROP CONSTRAINT citymodel_pk;
       citydb            postgres    false    301            �           2606    33142 1   cityobject_genericattrib cityobj_genericattrib_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT cityobj_genericattrib_pk PRIMARY KEY (id) WITH (fillfactor='100');
 [   ALTER TABLE ONLY citydb.cityobject_genericattrib DROP CONSTRAINT cityobj_genericattrib_pk;
       citydb            postgres    false    302                       2606    32757 &   cityobject_member cityobject_member_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_pk PRIMARY KEY (citymodel_id, cityobject_id) WITH (fillfactor='100');
 P   ALTER TABLE ONLY citydb.cityobject_member DROP CONSTRAINT cityobject_member_pk;
       citydb            postgres    false    237    237            �           2606    33086    cityobject cityobject_pk 
   CONSTRAINT     n   ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');
 B   ALTER TABLE ONLY citydb.cityobject DROP CONSTRAINT cityobject_pk;
       citydb            postgres    false    295                       2606    32771 "   cityobjectgroup cityobjectgroup_pk 
   CONSTRAINT     x   ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT cityobjectgroup_pk PRIMARY KEY (id) WITH (fillfactor='100');
 L   ALTER TABLE ONLY citydb.cityobjectgroup DROP CONSTRAINT cityobjectgroup_pk;
       citydb            postgres    false    241                       2606    32783    database_srs database_srs_pk 
   CONSTRAINT     t   ALTER TABLE ONLY citydb.database_srs
    ADD CONSTRAINT database_srs_pk PRIMARY KEY (srid) WITH (fillfactor='100');
 F   ALTER TABLE ONLY citydb.database_srs DROP CONSTRAINT database_srs_pk;
       citydb            postgres    false    243            �           2606    33150 (   external_reference external_reference_pk 
   CONSTRAINT     ~   ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT external_reference_pk PRIMARY KEY (id) WITH (fillfactor='100');
 R   ALTER TABLE ONLY citydb.external_reference DROP CONSTRAINT external_reference_pk;
       citydb            postgres    false    303                       2606    32763     generalization generalization_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT generalization_pk PRIMARY KEY (cityobject_id, generalizes_to_id) WITH (fillfactor='100');
 J   ALTER TABLE ONLY citydb.generalization DROP CONSTRAINT generalization_pk;
       citydb            postgres    false    239    239            N           2606    32806 (   generic_cityobject generic_cityobject_pk 
   CONSTRAINT     ~   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT generic_cityobject_pk PRIMARY KEY (id) WITH (fillfactor='100');
 R   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT generic_cityobject_pk;
       citydb            postgres    false    248            �           2606    33166    grid_coverage grid_coverage_pk 
   CONSTRAINT     t   ALTER TABLE ONLY citydb.grid_coverage
    ADD CONSTRAINT grid_coverage_pk PRIMARY KEY (id) WITH (fillfactor='100');
 H   ALTER TABLE ONLY citydb.grid_coverage DROP CONSTRAINT grid_coverage_pk;
       citydb            postgres    false    305                       2606    32776 *   group_to_cityobject group_to_cityobject_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_pk PRIMARY KEY (cityobject_id, cityobjectgroup_id) WITH (fillfactor='100');
 T   ALTER TABLE ONLY citydb.group_to_cityobject DROP CONSTRAINT group_to_cityobject_pk;
       citydb            postgres    false    242    242            �           2606    33102 &   implicit_geometry implicit_geometry_pk 
   CONSTRAINT     |   ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');
 P   ALTER TABLE ONLY citydb.implicit_geometry DROP CONSTRAINT implicit_geometry_pk;
       citydb            postgres    false    297                       2606    35251    index_table index_table_pkey 
   CONSTRAINT     Z   ALTER TABLE ONLY citydb.index_table
    ADD CONSTRAINT index_table_pkey PRIMARY KEY (id);
 F   ALTER TABLE ONLY citydb.index_table DROP CONSTRAINT index_table_pkey;
       citydb            postgres    false    315            �           2606    32934    land_use land_use_pk 
   CONSTRAINT     j   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_pk PRIMARY KEY (id) WITH (fillfactor='100');
 >   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_pk;
       citydb            postgres    false    270            �           2606    32885 $   masspoint_relief masspoint_relief_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.masspoint_relief DROP CONSTRAINT masspoint_relief_pk;
       citydb            postgres    false    263                       2606    32790    objectclass objectclass_pk 
   CONSTRAINT     p   ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_pk PRIMARY KEY (id) WITH (fillfactor='100');
 D   ALTER TABLE ONLY citydb.objectclass DROP CONSTRAINT objectclass_pk;
       citydb            postgres    false    244            �           2606    32840    opening opening_pk 
   CONSTRAINT     h   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_pk PRIMARY KEY (id) WITH (fillfactor='100');
 <   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_pk;
       citydb            postgres    false    254            �           2606    32845 2   opening_to_them_surface opening_to_them_surface_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT opening_to_them_surface_pk PRIMARY KEY (opening_id, thematic_surface_id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.opening_to_them_surface DROP CONSTRAINT opening_to_them_surface_pk;
       citydb            postgres    false    255    255            �           2606    32941    plant_cover plant_cover_pk 
   CONSTRAINT     p   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_pk PRIMARY KEY (id) WITH (fillfactor='100');
 D   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_pk;
       citydb            postgres    false    271                       2606    32974    raster_relief raster_relief_pk 
   CONSTRAINT     t   ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');
 H   ALTER TABLE ONLY citydb.raster_relief DROP CONSTRAINT raster_relief_pk;
       citydb            postgres    false    276            �           2606    32893 $   relief_component relief_component_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_component_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.relief_component DROP CONSTRAINT relief_component_pk;
       citydb            postgres    false    264            �           2606    32898 2   relief_feat_to_rel_comp relief_feat_to_rel_comp_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT relief_feat_to_rel_comp_pk PRIMARY KEY (relief_component_id, relief_feature_id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp DROP CONSTRAINT relief_feat_to_rel_comp_pk;
       citydb            postgres    false    265    265            �           2606    32906     relief_feature relief_feature_pk 
   CONSTRAINT     v   ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feature_pk PRIMARY KEY (id) WITH (fillfactor='100');
 J   ALTER TABLE ONLY citydb.relief_feature DROP CONSTRAINT relief_feature_pk;
       citydb            postgres    false    266            �           2606    32852    room room_pk 
   CONSTRAINT     b   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_pk PRIMARY KEY (id) WITH (fillfactor='100');
 6   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_pk;
       citydb            postgres    false    256            �           2606    33528    schema schema_pk 
   CONSTRAINT     f   ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_pk PRIMARY KEY (id) WITH (fillfactor='100');
 :   ALTER TABLE ONLY citydb.schema DROP CONSTRAINT schema_pk;
       citydb            postgres    false    308                       2606    33541 (   schema_referencing schema_referencing_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_pk PRIMARY KEY (referenced_id, referencing_id) WITH (fillfactor='100');
 R   ALTER TABLE ONLY citydb.schema_referencing DROP CONSTRAINT schema_referencing_pk;
       citydb            postgres    false    310    310            �           2606    33533 .   schema_to_objectclass schema_to_objectclass_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_pk PRIMARY KEY (schema_id, objectclass_id) WITH (fillfactor='100');
 X   ALTER TABLE ONLY citydb.schema_to_objectclass DROP CONSTRAINT schema_to_objectclass_pk;
       citydb            postgres    false    309    309            �           2606    32948 .   solitary_vegetat_object solitary_veg_object_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT solitary_veg_object_pk PRIMARY KEY (id) WITH (fillfactor='100');
 X   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT solitary_veg_object_pk;
       citydb            postgres    false    272            �           2606    33126    surface_data surface_data_pk 
   CONSTRAINT     r   ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_pk PRIMARY KEY (id) WITH (fillfactor='100');
 F   ALTER TABLE ONLY citydb.surface_data DROP CONSTRAINT surface_data_pk;
       citydb            postgres    false    300            �           2606    33110 $   surface_geometry surface_geometry_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geometry_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.surface_geometry DROP CONSTRAINT surface_geometry_pk;
       citydb            postgres    false    298            �           2606    33158    tex_image tex_image_pk 
   CONSTRAINT     l   ALTER TABLE ONLY citydb.tex_image
    ADD CONSTRAINT tex_image_pk PRIMARY KEY (id) WITH (fillfactor='100');
 @   ALTER TABLE ONLY citydb.tex_image DROP CONSTRAINT tex_image_pk;
       citydb            postgres    false    304            �           2606    32866    textureparam textureparam_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT textureparam_pk PRIMARY KEY (surface_geometry_id, surface_data_id) WITH (fillfactor='100');
 F   ALTER TABLE ONLY citydb.textureparam DROP CONSTRAINT textureparam_pk;
       citydb            postgres    false    260    260            �           2606    32857 $   thematic_surface thematic_surface_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT thematic_surface_pk;
       citydb            postgres    false    257            �           2606    32913    tin_relief tin_relief_pk 
   CONSTRAINT     n   ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_pk PRIMARY KEY (id) WITH (fillfactor='100');
 B   ALTER TABLE ONLY citydb.tin_relief DROP CONSTRAINT tin_relief_pk;
       citydb            postgres    false    267            �           2606    32927    traffic_area traffic_area_pk 
   CONSTRAINT     r   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_pk PRIMARY KEY (id) WITH (fillfactor='100');
 F   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_pk;
       citydb            postgres    false    269            �           2606    32920 0   transportation_complex transportation_complex_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT transportation_complex_pk PRIMARY KEY (id) WITH (fillfactor='100');
 Z   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT transportation_complex_pk;
       citydb            postgres    false    268            X           2606    33020 $   tunnel_furniture tunnel_furniture_pk 
   CONSTRAINT     z   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furniture_pk PRIMARY KEY (id) WITH (fillfactor='100');
 N   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furniture_pk;
       citydb            postgres    false    284            -           2606    32993 *   tunnel_hollow_space tunnel_hollow_space_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tunnel_hollow_space_pk PRIMARY KEY (id) WITH (fillfactor='100');
 T   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tunnel_hollow_space_pk;
       citydb            postgres    false    279            P           2606    33013 *   tunnel_installation tunnel_installation_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_installation_pk PRIMARY KEY (id) WITH (fillfactor='100');
 T   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_installation_pk;
       citydb            postgres    false    283            '           2606    32986 2   tunnel_open_to_them_srf tunnel_open_to_them_srf_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tunnel_open_to_them_srf_pk PRIMARY KEY (tunnel_opening_id, tunnel_thematic_surface_id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf DROP CONSTRAINT tunnel_open_to_them_srf_pk;
       citydb            postgres    false    278    278            ?           2606    33006     tunnel_opening tunnel_opening_pk 
   CONSTRAINT     v   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_opening_pk PRIMARY KEY (id) WITH (fillfactor='100');
 J   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_opening_pk;
       citydb            postgres    false    282            "           2606    32981    tunnel tunnel_pk 
   CONSTRAINT     f   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_pk PRIMARY KEY (id) WITH (fillfactor='100');
 :   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_pk;
       citydb            postgres    false    277            6           2606    32998 2   tunnel_thematic_surface tunnel_thematic_surface_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tunnel_thematic_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');
 \   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tunnel_thematic_surface_pk;
       citydb            postgres    false    280                       2606    32960 0   waterbod_to_waterbnd_srf waterbod_to_waterbnd_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_pk PRIMARY KEY (waterboundary_surface_id, waterbody_id) WITH (fillfactor='100');
 Z   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf DROP CONSTRAINT waterbod_to_waterbnd_pk;
       citydb            postgres    false    274    274                       2606    32955    waterbody waterbody_pk 
   CONSTRAINT     l   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_pk PRIMARY KEY (id) WITH (fillfactor='100');
 @   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_pk;
       citydb            postgres    false    273                       2606    32967 .   waterboundary_surface waterboundary_surface_pk 
   CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterboundary_surface_pk PRIMARY KEY (id) WITH (fillfactor='100');
 X   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterboundary_surface_pk;
       citydb            postgres    false    275            �           1259    33519    address_inx    INDEX     Q   CREATE INDEX address_inx ON citydb.address USING btree (gmlid, gmlid_codespace);
    DROP INDEX citydb.address_inx;
       citydb            postgres    false    299    299            �           1259    37409    address_point_spx    INDEX     K   CREATE INDEX address_point_spx ON citydb.address USING gist (multi_point);
 %   DROP INDEX citydb.address_point_spx;
       citydb            postgres    false    299    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33490    address_to_bridge_fkx    INDEX     p   CREATE INDEX address_to_bridge_fkx ON citydb.address_to_bridge USING btree (address_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.address_to_bridge_fkx;
       citydb            postgres    false    293            �           1259    33491    address_to_bridge_fkx1    INDEX     p   CREATE INDEX address_to_bridge_fkx1 ON citydb.address_to_bridge USING btree (bridge_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.address_to_bridge_fkx1;
       citydb            postgres    false    293            O           1259    33224    address_to_building_fkx    INDEX     t   CREATE INDEX address_to_building_fkx ON citydb.address_to_building USING btree (address_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.address_to_building_fkx;
       citydb            postgres    false    250            P           1259    33225    address_to_building_fkx1    INDEX     v   CREATE INDEX address_to_building_fkx1 ON citydb.address_to_building USING btree (building_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.address_to_building_fkx1;
       citydb            postgres    false    250            �           1259    33287    app_to_surf_data_fkx    INDEX     y   CREATE INDEX app_to_surf_data_fkx ON citydb.appear_to_surface_data USING btree (surface_data_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.app_to_surf_data_fkx;
       citydb            postgres    false    261            �           1259    33288    app_to_surf_data_fkx1    INDEX     x   CREATE INDEX app_to_surf_data_fkx1 ON citydb.appear_to_surface_data USING btree (appearance_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.app_to_surf_data_fkx1;
       citydb            postgres    false    261            �           1259    33497    appearance_citymodel_fkx    INDEX     n   CREATE INDEX appearance_citymodel_fkx ON citydb.appearance USING btree (citymodel_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.appearance_citymodel_fkx;
       citydb            postgres    false    296            �           1259    33498    appearance_cityobject_fkx    INDEX     p   CREATE INDEX appearance_cityobject_fkx ON citydb.appearance USING btree (cityobject_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.appearance_cityobject_fkx;
       citydb            postgres    false    296            �           1259    33495    appearance_inx    INDEX     n   CREATE INDEX appearance_inx ON citydb.appearance USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');
 "   DROP INDEX citydb.appearance_inx;
       citydb            postgres    false    296    296            �           1259    33496    appearance_theme_inx    INDEX     c   CREATE INDEX appearance_theme_inx ON citydb.appearance USING btree (theme) WITH (fillfactor='90');
 (   DROP INDEX citydb.appearance_theme_inx;
       citydb            postgres    false    296            i           1259    33246    bldg_furn_lod4brep_fkx    INDEX     t   CREATE INDEX bldg_furn_lod4brep_fkx ON citydb.building_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_furn_lod4brep_fkx;
       citydb            postgres    false    252            j           1259    33248    bldg_furn_lod4impl_fkx    INDEX     |   CREATE INDEX bldg_furn_lod4impl_fkx ON citydb.building_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_furn_lod4impl_fkx;
       citydb            postgres    false    252            k           1259    35983    bldg_furn_lod4refpt_spx    INDEX     h   CREATE INDEX bldg_furn_lod4refpt_spx ON citydb.building_furniture USING gist (lod4_implicit_ref_point);
 +   DROP INDEX citydb.bldg_furn_lod4refpt_spx;
       citydb            postgres    false    252    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            l           1259    35971    bldg_furn_lod4xgeom_spx    INDEX     `   CREATE INDEX bldg_furn_lod4xgeom_spx ON citydb.building_furniture USING gist (lod4_other_geom);
 +   DROP INDEX citydb.bldg_furn_lod4xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    252            m           1259    33550    bldg_furn_objclass_fkx    INDEX     v   CREATE INDEX bldg_furn_objclass_fkx ON citydb.building_furniture USING btree (objectclass_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_furn_objclass_fkx;
       citydb            postgres    false    252            n           1259    33245    bldg_furn_room_fkx    INDEX     k   CREATE INDEX bldg_furn_room_fkx ON citydb.building_furniture USING btree (room_id) WITH (fillfactor='90');
 &   DROP INDEX citydb.bldg_furn_room_fkx;
       citydb            postgres    false    252            q           1259    33251    bldg_inst_building_fkx    INDEX     v   CREATE INDEX bldg_inst_building_fkx ON citydb.building_installation USING btree (building_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_building_fkx;
       citydb            postgres    false    253            r           1259    33253    bldg_inst_lod2brep_fkx    INDEX     w   CREATE INDEX bldg_inst_lod2brep_fkx ON citydb.building_installation USING btree (lod2_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod2brep_fkx;
       citydb            postgres    false    253            s           1259    33259    bldg_inst_lod2impl_fkx    INDEX        CREATE INDEX bldg_inst_lod2impl_fkx ON citydb.building_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod2impl_fkx;
       citydb            postgres    false    253            t           1259    36067    bldg_inst_lod2refpt_spx    INDEX     k   CREATE INDEX bldg_inst_lod2refpt_spx ON citydb.building_installation USING gist (lod2_implicit_ref_point);
 +   DROP INDEX citydb.bldg_inst_lod2refpt_spx;
       citydb            postgres    false    253    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            u           1259    36004    bldg_inst_lod2xgeom_spx    INDEX     c   CREATE INDEX bldg_inst_lod2xgeom_spx ON citydb.building_installation USING gist (lod2_other_geom);
 +   DROP INDEX citydb.bldg_inst_lod2xgeom_spx;
       citydb            postgres    false    253    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            v           1259    33254    bldg_inst_lod3brep_fkx    INDEX     w   CREATE INDEX bldg_inst_lod3brep_fkx ON citydb.building_installation USING btree (lod3_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod3brep_fkx;
       citydb            postgres    false    253            w           1259    33260    bldg_inst_lod3impl_fkx    INDEX        CREATE INDEX bldg_inst_lod3impl_fkx ON citydb.building_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod3impl_fkx;
       citydb            postgres    false    253            x           1259    36088    bldg_inst_lod3refpt_spx    INDEX     k   CREATE INDEX bldg_inst_lod3refpt_spx ON citydb.building_installation USING gist (lod3_implicit_ref_point);
 +   DROP INDEX citydb.bldg_inst_lod3refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    253            y           1259    36025    bldg_inst_lod3xgeom_spx    INDEX     c   CREATE INDEX bldg_inst_lod3xgeom_spx ON citydb.building_installation USING gist (lod3_other_geom);
 +   DROP INDEX citydb.bldg_inst_lod3xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    253            z           1259    33255    bldg_inst_lod4brep_fkx    INDEX     w   CREATE INDEX bldg_inst_lod4brep_fkx ON citydb.building_installation USING btree (lod4_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod4brep_fkx;
       citydb            postgres    false    253            {           1259    33261    bldg_inst_lod4impl_fkx    INDEX        CREATE INDEX bldg_inst_lod4impl_fkx ON citydb.building_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bldg_inst_lod4impl_fkx;
       citydb            postgres    false    253            |           1259    36109    bldg_inst_lod4refpt_spx    INDEX     k   CREATE INDEX bldg_inst_lod4refpt_spx ON citydb.building_installation USING gist (lod4_implicit_ref_point);
 +   DROP INDEX citydb.bldg_inst_lod4refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    253            }           1259    36046    bldg_inst_lod4xgeom_spx    INDEX     c   CREATE INDEX bldg_inst_lod4xgeom_spx ON citydb.building_installation USING gist (lod4_other_geom);
 +   DROP INDEX citydb.bldg_inst_lod4xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    253            ~           1259    33250    bldg_inst_objclass_fkx    INDEX     b   CREATE INDEX bldg_inst_objclass_fkx ON citydb.building_installation USING btree (objectclass_id);
 *   DROP INDEX citydb.bldg_inst_objclass_fkx;
       citydb            postgres    false    253                       1259    33252    bldg_inst_room_fkx    INDEX     n   CREATE INDEX bldg_inst_room_fkx ON citydb.building_installation USING btree (room_id) WITH (fillfactor='90');
 &   DROP INDEX citydb.bldg_inst_room_fkx;
       citydb            postgres    false    253            �           1259    33456    brd_open_to_them_srf_fkx    INDEX     �   CREATE INDEX brd_open_to_them_srf_fkx ON citydb.bridge_open_to_them_srf USING btree (bridge_opening_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.brd_open_to_them_srf_fkx;
       citydb            postgres    false    289            �           1259    33457    brd_open_to_them_srf_fkx1    INDEX     �   CREATE INDEX brd_open_to_them_srf_fkx1 ON citydb.bridge_open_to_them_srf USING btree (bridge_thematic_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_open_to_them_srf_fkx1;
       citydb            postgres    false    289            �           1259    33465    brd_them_srf_brd_const_fkx    INDEX     �   CREATE INDEX brd_them_srf_brd_const_fkx ON citydb.bridge_thematic_surface USING btree (bridge_constr_element_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.brd_them_srf_brd_const_fkx;
       citydb            postgres    false    291            �           1259    33464    brd_them_srf_brd_inst_fkx    INDEX     �   CREATE INDEX brd_them_srf_brd_inst_fkx ON citydb.bridge_thematic_surface USING btree (bridge_installation_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_brd_inst_fkx;
       citydb            postgres    false    291            �           1259    33463    brd_them_srf_brd_room_fkx    INDEX     ~   CREATE INDEX brd_them_srf_brd_room_fkx ON citydb.bridge_thematic_surface USING btree (bridge_room_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_brd_room_fkx;
       citydb            postgres    false    291            �           1259    33462    brd_them_srf_bridge_fkx    INDEX     w   CREATE INDEX brd_them_srf_bridge_fkx ON citydb.bridge_thematic_surface USING btree (bridge_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.brd_them_srf_bridge_fkx;
       citydb            postgres    false    291            �           1259    33466    brd_them_srf_lod2msrf_fkx    INDEX     �   CREATE INDEX brd_them_srf_lod2msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_lod2msrf_fkx;
       citydb            postgres    false    291            �           1259    33467    brd_them_srf_lod3msrf_fkx    INDEX     �   CREATE INDEX brd_them_srf_lod3msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_lod3msrf_fkx;
       citydb            postgres    false    291            �           1259    33468    brd_them_srf_lod4msrf_fkx    INDEX     �   CREATE INDEX brd_them_srf_lod4msrf_fkx ON citydb.bridge_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_lod4msrf_fkx;
       citydb            postgres    false    291            �           1259    33461    brd_them_srf_objclass_fkx    INDEX     ~   CREATE INDEX brd_them_srf_objclass_fkx ON citydb.bridge_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.brd_them_srf_objclass_fkx;
       citydb            postgres    false    291            �           1259    36669    breakline_break_spx    INDEX     V   CREATE INDEX breakline_break_spx ON citydb.breakline_relief USING gist (break_lines);
 '   DROP INDEX citydb.breakline_break_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    262            �           1259    33544    breakline_rel_objclass_fkx    INDEX     x   CREATE INDEX breakline_rel_objclass_fkx ON citydb.breakline_relief USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.breakline_rel_objclass_fkx;
       citydb            postgres    false    262            �           1259    36660    breakline_ridge_spx    INDEX     `   CREATE INDEX breakline_ridge_spx ON citydb.breakline_relief USING gist (ridge_or_valley_lines);
 '   DROP INDEX citydb.breakline_ridge_spx;
       citydb            postgres    false    262    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37702    bridge_const_lod1refpt_spx    INDEX     n   CREATE INDEX bridge_const_lod1refpt_spx ON citydb.bridge_constr_element USING gist (lod1_implicit_ref_point);
 .   DROP INDEX citydb.bridge_const_lod1refpt_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37590    bridge_const_lod1xgeom_spx    INDEX     f   CREATE INDEX bridge_const_lod1xgeom_spx ON citydb.bridge_constr_element USING gist (lod1_other_geom);
 .   DROP INDEX citydb.bridge_const_lod1xgeom_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37730    bridge_const_lod2refpt_spx    INDEX     n   CREATE INDEX bridge_const_lod2refpt_spx ON citydb.bridge_constr_element USING gist (lod2_implicit_ref_point);
 .   DROP INDEX citydb.bridge_const_lod2refpt_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37618    bridge_const_lod2xgeom_spx    INDEX     f   CREATE INDEX bridge_const_lod2xgeom_spx ON citydb.bridge_constr_element USING gist (lod2_other_geom);
 .   DROP INDEX citydb.bridge_const_lod2xgeom_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37758    bridge_const_lod3refpt_spx    INDEX     n   CREATE INDEX bridge_const_lod3refpt_spx ON citydb.bridge_constr_element USING gist (lod3_implicit_ref_point);
 .   DROP INDEX citydb.bridge_const_lod3refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    37646    bridge_const_lod3xgeom_spx    INDEX     f   CREATE INDEX bridge_const_lod3xgeom_spx ON citydb.bridge_constr_element USING gist (lod3_other_geom);
 .   DROP INDEX citydb.bridge_const_lod3xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    37786    bridge_const_lod4refpt_spx    INDEX     n   CREATE INDEX bridge_const_lod4refpt_spx ON citydb.bridge_constr_element USING gist (lod4_implicit_ref_point);
 .   DROP INDEX citydb.bridge_const_lod4refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    37674    bridge_const_lod4xgeom_spx    INDEX     f   CREATE INDEX bridge_const_lod4xgeom_spx ON citydb.bridge_constr_element USING gist (lod4_other_geom);
 .   DROP INDEX citydb.bridge_const_lod4xgeom_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33469    bridge_constr_bridge_fkx    INDEX     v   CREATE INDEX bridge_constr_bridge_fkx ON citydb.bridge_constr_element USING btree (bridge_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_constr_bridge_fkx;
       citydb            postgres    false    292            �           1259    33474    bridge_constr_lod1brep_fkx    INDEX     {   CREATE INDEX bridge_constr_lod1brep_fkx ON citydb.bridge_constr_element USING btree (lod1_brep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod1brep_fkx;
       citydb            postgres    false    292            �           1259    33482    bridge_constr_lod1impl_fkx    INDEX     �   CREATE INDEX bridge_constr_lod1impl_fkx ON citydb.bridge_constr_element USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod1impl_fkx;
       citydb            postgres    false    292            �           1259    37478    bridge_constr_lod1terr_spx    INDEX     p   CREATE INDEX bridge_constr_lod1terr_spx ON citydb.bridge_constr_element USING gist (lod1_terrain_intersection);
 .   DROP INDEX citydb.bridge_constr_lod1terr_spx;
       citydb            postgres    false    292    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33475    bridge_constr_lod2brep_fkx    INDEX     {   CREATE INDEX bridge_constr_lod2brep_fkx ON citydb.bridge_constr_element USING btree (lod2_brep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod2brep_fkx;
       citydb            postgres    false    292            �           1259    33483    bridge_constr_lod2impl_fkx    INDEX     �   CREATE INDEX bridge_constr_lod2impl_fkx ON citydb.bridge_constr_element USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod2impl_fkx;
       citydb            postgres    false    292            �           1259    37506    bridge_constr_lod2terr_spx    INDEX     p   CREATE INDEX bridge_constr_lod2terr_spx ON citydb.bridge_constr_element USING gist (lod2_terrain_intersection);
 .   DROP INDEX citydb.bridge_constr_lod2terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    33476    bridge_constr_lod3brep_fkx    INDEX     {   CREATE INDEX bridge_constr_lod3brep_fkx ON citydb.bridge_constr_element USING btree (lod3_brep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod3brep_fkx;
       citydb            postgres    false    292            �           1259    33484    bridge_constr_lod3impl_fkx    INDEX     �   CREATE INDEX bridge_constr_lod3impl_fkx ON citydb.bridge_constr_element USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod3impl_fkx;
       citydb            postgres    false    292            �           1259    37534    bridge_constr_lod3terr_spx    INDEX     p   CREATE INDEX bridge_constr_lod3terr_spx ON citydb.bridge_constr_element USING gist (lod3_terrain_intersection);
 .   DROP INDEX citydb.bridge_constr_lod3terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    33477    bridge_constr_lod4brep_fkx    INDEX     {   CREATE INDEX bridge_constr_lod4brep_fkx ON citydb.bridge_constr_element USING btree (lod4_brep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod4brep_fkx;
       citydb            postgres    false    292            �           1259    33485    bridge_constr_lod4impl_fkx    INDEX     �   CREATE INDEX bridge_constr_lod4impl_fkx ON citydb.bridge_constr_element USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_lod4impl_fkx;
       citydb            postgres    false    292            �           1259    37562    bridge_constr_lod4terr_spx    INDEX     p   CREATE INDEX bridge_constr_lod4terr_spx ON citydb.bridge_constr_element USING gist (lod4_terrain_intersection);
 .   DROP INDEX citydb.bridge_constr_lod4terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    292            �           1259    33546    bridge_constr_objclass_fkx    INDEX     }   CREATE INDEX bridge_constr_objclass_fkx ON citydb.bridge_constr_element USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.bridge_constr_objclass_fkx;
       citydb            postgres    false    292            m           1259    33428    bridge_furn_brd_room_fkx    INDEX     v   CREATE INDEX bridge_furn_brd_room_fkx ON citydb.bridge_furniture USING btree (bridge_room_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_furn_brd_room_fkx;
       citydb            postgres    false    286            n           1259    33429    bridge_furn_lod4brep_fkx    INDEX     t   CREATE INDEX bridge_furn_lod4brep_fkx ON citydb.bridge_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_furn_lod4brep_fkx;
       citydb            postgres    false    286            o           1259    33431    bridge_furn_lod4impl_fkx    INDEX     |   CREATE INDEX bridge_furn_lod4impl_fkx ON citydb.bridge_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_furn_lod4impl_fkx;
       citydb            postgres    false    286            p           1259    37251    bridge_furn_lod4refpt_spx    INDEX     h   CREATE INDEX bridge_furn_lod4refpt_spx ON citydb.bridge_furniture USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.bridge_furn_lod4refpt_spx;
       citydb            postgres    false    286    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            q           1259    37239    bridge_furn_lod4xgeom_spx    INDEX     `   CREATE INDEX bridge_furn_lod4xgeom_spx ON citydb.bridge_furniture USING gist (lod4_other_geom);
 -   DROP INDEX citydb.bridge_furn_lod4xgeom_spx;
       citydb            postgres    false    286    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            r           1259    33547    bridge_furn_objclass_fkx    INDEX     v   CREATE INDEX bridge_furn_objclass_fkx ON citydb.bridge_furniture USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_furn_objclass_fkx;
       citydb            postgres    false    286            u           1259    33435    bridge_inst_brd_room_fkx    INDEX     y   CREATE INDEX bridge_inst_brd_room_fkx ON citydb.bridge_installation USING btree (bridge_room_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_brd_room_fkx;
       citydb            postgres    false    287            v           1259    33434    bridge_inst_bridge_fkx    INDEX     r   CREATE INDEX bridge_inst_bridge_fkx ON citydb.bridge_installation USING btree (bridge_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bridge_inst_bridge_fkx;
       citydb            postgres    false    287            w           1259    33436    bridge_inst_lod2brep_fkx    INDEX     w   CREATE INDEX bridge_inst_lod2brep_fkx ON citydb.bridge_installation USING btree (lod2_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod2brep_fkx;
       citydb            postgres    false    287            x           1259    33442    bridge_inst_lod2impl_fkx    INDEX        CREATE INDEX bridge_inst_lod2impl_fkx ON citydb.bridge_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod2impl_fkx;
       citydb            postgres    false    287            y           1259    37335    bridge_inst_lod2refpt_spx    INDEX     k   CREATE INDEX bridge_inst_lod2refpt_spx ON citydb.bridge_installation USING gist (lod2_implicit_ref_point);
 -   DROP INDEX citydb.bridge_inst_lod2refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    287            z           1259    37272    bridge_inst_lod2xgeom_spx    INDEX     c   CREATE INDEX bridge_inst_lod2xgeom_spx ON citydb.bridge_installation USING gist (lod2_other_geom);
 -   DROP INDEX citydb.bridge_inst_lod2xgeom_spx;
       citydb            postgres    false    287    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            {           1259    33437    bridge_inst_lod3brep_fkx    INDEX     w   CREATE INDEX bridge_inst_lod3brep_fkx ON citydb.bridge_installation USING btree (lod3_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod3brep_fkx;
       citydb            postgres    false    287            |           1259    33443    bridge_inst_lod3impl_fkx    INDEX        CREATE INDEX bridge_inst_lod3impl_fkx ON citydb.bridge_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod3impl_fkx;
       citydb            postgres    false    287            }           1259    37356    bridge_inst_lod3refpt_spx    INDEX     k   CREATE INDEX bridge_inst_lod3refpt_spx ON citydb.bridge_installation USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.bridge_inst_lod3refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    287            ~           1259    37293    bridge_inst_lod3xgeom_spx    INDEX     c   CREATE INDEX bridge_inst_lod3xgeom_spx ON citydb.bridge_installation USING gist (lod3_other_geom);
 -   DROP INDEX citydb.bridge_inst_lod3xgeom_spx;
       citydb            postgres    false    287    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    33438    bridge_inst_lod4brep_fkx    INDEX     w   CREATE INDEX bridge_inst_lod4brep_fkx ON citydb.bridge_installation USING btree (lod4_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod4brep_fkx;
       citydb            postgres    false    287            �           1259    33444    bridge_inst_lod4impl_fkx    INDEX        CREATE INDEX bridge_inst_lod4impl_fkx ON citydb.bridge_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_inst_lod4impl_fkx;
       citydb            postgres    false    287            �           1259    37377    bridge_inst_lod4refpt_spx    INDEX     k   CREATE INDEX bridge_inst_lod4refpt_spx ON citydb.bridge_installation USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.bridge_inst_lod4refpt_spx;
       citydb            postgres    false    287    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    37314    bridge_inst_lod4xgeom_spx    INDEX     c   CREATE INDEX bridge_inst_lod4xgeom_spx ON citydb.bridge_installation USING gist (lod4_other_geom);
 -   DROP INDEX citydb.bridge_inst_lod4xgeom_spx;
       citydb            postgres    false    287    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33433    bridge_inst_objclass_fkx    INDEX     b   CREATE INDEX bridge_inst_objclass_fkx ON citydb.bridge_installation USING btree (objectclass_id);
 ,   DROP INDEX citydb.bridge_inst_objclass_fkx;
       citydb            postgres    false    287            Y           1259    33420    bridge_lod1msrf_fkx    INDEX     n   CREATE INDEX bridge_lod1msrf_fkx ON citydb.bridge USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.bridge_lod1msrf_fkx;
       citydb            postgres    false    285            Z           1259    33424    bridge_lod1solid_fkx    INDEX     g   CREATE INDEX bridge_lod1solid_fkx ON citydb.bridge USING btree (lod1_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.bridge_lod1solid_fkx;
       citydb            postgres    false    285            [           1259    37082    bridge_lod1terr_spx    INDEX     Z   CREATE INDEX bridge_lod1terr_spx ON citydb.bridge USING gist (lod1_terrain_intersection);
 '   DROP INDEX citydb.bridge_lod1terr_spx;
       citydb            postgres    false    285    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            \           1259    37179    bridge_lod2curve_spx    INDEX     R   CREATE INDEX bridge_lod2curve_spx ON citydb.bridge USING gist (lod2_multi_curve);
 (   DROP INDEX citydb.bridge_lod2curve_spx;
       citydb            postgres    false    285    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            ]           1259    33421    bridge_lod2msrf_fkx    INDEX     n   CREATE INDEX bridge_lod2msrf_fkx ON citydb.bridge USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.bridge_lod2msrf_fkx;
       citydb            postgres    false    285            ^           1259    33425    bridge_lod2solid_fkx    INDEX     g   CREATE INDEX bridge_lod2solid_fkx ON citydb.bridge USING btree (lod2_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.bridge_lod2solid_fkx;
       citydb            postgres    false    285            _           1259    37107    bridge_lod2terr_spx    INDEX     Z   CREATE INDEX bridge_lod2terr_spx ON citydb.bridge USING gist (lod2_terrain_intersection);
 '   DROP INDEX citydb.bridge_lod2terr_spx;
       citydb            postgres    false    285    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            `           1259    37203    bridge_lod3curve_spx    INDEX     R   CREATE INDEX bridge_lod3curve_spx ON citydb.bridge USING gist (lod3_multi_curve);
 (   DROP INDEX citydb.bridge_lod3curve_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    285            a           1259    33422    bridge_lod3msrf_fkx    INDEX     n   CREATE INDEX bridge_lod3msrf_fkx ON citydb.bridge USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.bridge_lod3msrf_fkx;
       citydb            postgres    false    285            b           1259    33426    bridge_lod3solid_fkx    INDEX     g   CREATE INDEX bridge_lod3solid_fkx ON citydb.bridge USING btree (lod3_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.bridge_lod3solid_fkx;
       citydb            postgres    false    285            c           1259    37131    bridge_lod3terr_spx    INDEX     Z   CREATE INDEX bridge_lod3terr_spx ON citydb.bridge USING gist (lod3_terrain_intersection);
 '   DROP INDEX citydb.bridge_lod3terr_spx;
       citydb            postgres    false    285    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            d           1259    37227    bridge_lod4curve_spx    INDEX     R   CREATE INDEX bridge_lod4curve_spx ON citydb.bridge USING gist (lod4_multi_curve);
 (   DROP INDEX citydb.bridge_lod4curve_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    285            e           1259    33423    bridge_lod4msrf_fkx    INDEX     n   CREATE INDEX bridge_lod4msrf_fkx ON citydb.bridge USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.bridge_lod4msrf_fkx;
       citydb            postgres    false    285            f           1259    33427    bridge_lod4solid_fkx    INDEX     g   CREATE INDEX bridge_lod4solid_fkx ON citydb.bridge USING btree (lod4_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.bridge_lod4solid_fkx;
       citydb            postgres    false    285            g           1259    37155    bridge_lod4terr_spx    INDEX     Z   CREATE INDEX bridge_lod4terr_spx ON citydb.bridge USING gist (lod4_terrain_intersection);
 '   DROP INDEX citydb.bridge_lod4terr_spx;
       citydb            postgres    false    285    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            h           1259    33545    bridge_objectclass_fkx    INDEX     j   CREATE INDEX bridge_objectclass_fkx ON citydb.bridge USING btree (objectclass_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bridge_objectclass_fkx;
       citydb            postgres    false    285            �           1259    33449    bridge_open_address_fkx    INDEX     o   CREATE INDEX bridge_open_address_fkx ON citydb.bridge_opening USING btree (address_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.bridge_open_address_fkx;
       citydb            postgres    false    288            �           1259    33452    bridge_open_lod3impl_fkx    INDEX     z   CREATE INDEX bridge_open_lod3impl_fkx ON citydb.bridge_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_open_lod3impl_fkx;
       citydb            postgres    false    288            �           1259    33450    bridge_open_lod3msrf_fkx    INDEX     {   CREATE INDEX bridge_open_lod3msrf_fkx ON citydb.bridge_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_open_lod3msrf_fkx;
       citydb            postgres    false    288            �           1259    37436    bridge_open_lod3refpt_spx    INDEX     f   CREATE INDEX bridge_open_lod3refpt_spx ON citydb.bridge_opening USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.bridge_open_lod3refpt_spx;
       citydb            postgres    false    288    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33453    bridge_open_lod4impl_fkx    INDEX     z   CREATE INDEX bridge_open_lod4impl_fkx ON citydb.bridge_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_open_lod4impl_fkx;
       citydb            postgres    false    288            �           1259    33451    bridge_open_lod4msrf_fkx    INDEX     {   CREATE INDEX bridge_open_lod4msrf_fkx ON citydb.bridge_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_open_lod4msrf_fkx;
       citydb            postgres    false    288            �           1259    37450    bridge_open_lod4refpt_spx    INDEX     f   CREATE INDEX bridge_open_lod4refpt_spx ON citydb.bridge_opening USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.bridge_open_lod4refpt_spx;
       citydb            postgres    false    288    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33448    bridge_open_objclass_fkx    INDEX     t   CREATE INDEX bridge_open_objclass_fkx ON citydb.bridge_opening USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_open_objclass_fkx;
       citydb            postgres    false    288            i           1259    33411    bridge_parent_fkx    INDEX     g   CREATE INDEX bridge_parent_fkx ON citydb.bridge USING btree (bridge_parent_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.bridge_parent_fkx;
       citydb            postgres    false    285            �           1259    33458    bridge_room_bridge_fkx    INDEX     j   CREATE INDEX bridge_room_bridge_fkx ON citydb.bridge_room USING btree (bridge_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.bridge_room_bridge_fkx;
       citydb            postgres    false    290            �           1259    33459    bridge_room_lod4msrf_fkx    INDEX     x   CREATE INDEX bridge_room_lod4msrf_fkx ON citydb.bridge_room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_room_lod4msrf_fkx;
       citydb            postgres    false    290            �           1259    33460    bridge_room_lod4solid_fkx    INDEX     q   CREATE INDEX bridge_room_lod4solid_fkx ON citydb.bridge_room USING btree (lod4_solid_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.bridge_room_lod4solid_fkx;
       citydb            postgres    false    290            �           1259    33548    bridge_room_objclass_fkx    INDEX     q   CREATE INDEX bridge_room_objclass_fkx ON citydb.bridge_room USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.bridge_room_objclass_fkx;
       citydb            postgres    false    290            l           1259    33412    bridge_root_fkx    INDEX     c   CREATE INDEX bridge_root_fkx ON citydb.bridge USING btree (bridge_root_id) WITH (fillfactor='90');
 #   DROP INDEX citydb.bridge_root_fkx;
       citydb            postgres    false    285            S           1259    33235    building_lod0footprint_fkx    INDEX     s   CREATE INDEX building_lod0footprint_fkx ON citydb.building USING btree (lod0_footprint_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.building_lod0footprint_fkx;
       citydb            postgres    false    251            T           1259    33236    building_lod0roofprint_fkx    INDEX     s   CREATE INDEX building_lod0roofprint_fkx ON citydb.building USING btree (lod0_roofprint_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.building_lod0roofprint_fkx;
       citydb            postgres    false    251            U           1259    33237    building_lod1msrf_fkx    INDEX     r   CREATE INDEX building_lod1msrf_fkx ON citydb.building USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.building_lod1msrf_fkx;
       citydb            postgres    false    251            V           1259    33241    building_lod1solid_fkx    INDEX     k   CREATE INDEX building_lod1solid_fkx ON citydb.building USING btree (lod1_solid_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.building_lod1solid_fkx;
       citydb            postgres    false    251            W           1259    36487    building_lod1terr_spx    INDEX     ^   CREATE INDEX building_lod1terr_spx ON citydb.building USING gist (lod1_terrain_intersection);
 )   DROP INDEX citydb.building_lod1terr_spx;
       citydb            postgres    false    251    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            X           1259    36591    building_lod2curve_spx    INDEX     V   CREATE INDEX building_lod2curve_spx ON citydb.building USING gist (lod2_multi_curve);
 *   DROP INDEX citydb.building_lod2curve_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    251            Y           1259    33238    building_lod2msrf_fkx    INDEX     r   CREATE INDEX building_lod2msrf_fkx ON citydb.building USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.building_lod2msrf_fkx;
       citydb            postgres    false    251            Z           1259    33242    building_lod2solid_fkx    INDEX     k   CREATE INDEX building_lod2solid_fkx ON citydb.building USING btree (lod2_solid_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.building_lod2solid_fkx;
       citydb            postgres    false    251            [           1259    36513    building_lod2terr_spx    INDEX     ^   CREATE INDEX building_lod2terr_spx ON citydb.building USING gist (lod2_terrain_intersection);
 )   DROP INDEX citydb.building_lod2terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    251            \           1259    36617    building_lod3curve_spx    INDEX     V   CREATE INDEX building_lod3curve_spx ON citydb.building USING gist (lod3_multi_curve);
 *   DROP INDEX citydb.building_lod3curve_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    251            ]           1259    33239    building_lod3msrf_fkx    INDEX     r   CREATE INDEX building_lod3msrf_fkx ON citydb.building USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.building_lod3msrf_fkx;
       citydb            postgres    false    251            ^           1259    33243    building_lod3solid_fkx    INDEX     k   CREATE INDEX building_lod3solid_fkx ON citydb.building USING btree (lod3_solid_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.building_lod3solid_fkx;
       citydb            postgres    false    251            _           1259    36539    building_lod3terr_spx    INDEX     ^   CREATE INDEX building_lod3terr_spx ON citydb.building USING gist (lod3_terrain_intersection);
 )   DROP INDEX citydb.building_lod3terr_spx;
       citydb            postgres    false    251    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            `           1259    36643    building_lod4curve_spx    INDEX     V   CREATE INDEX building_lod4curve_spx ON citydb.building USING gist (lod4_multi_curve);
 *   DROP INDEX citydb.building_lod4curve_spx;
       citydb            postgres    false    251    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            a           1259    33240    building_lod4msrf_fkx    INDEX     r   CREATE INDEX building_lod4msrf_fkx ON citydb.building USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.building_lod4msrf_fkx;
       citydb            postgres    false    251            b           1259    33244    building_lod4solid_fkx    INDEX     k   CREATE INDEX building_lod4solid_fkx ON citydb.building USING btree (lod4_solid_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.building_lod4solid_fkx;
       citydb            postgres    false    251            c           1259    36565    building_lod4terr_spx    INDEX     ^   CREATE INDEX building_lod4terr_spx ON citydb.building USING gist (lod4_terrain_intersection);
 )   DROP INDEX citydb.building_lod4terr_spx;
       citydb            postgres    false    251    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            d           1259    33549    building_objectclass_fkx    INDEX     n   CREATE INDEX building_objectclass_fkx ON citydb.building USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.building_objectclass_fkx;
       citydb            postgres    false    251            e           1259    33226    building_parent_fkx    INDEX     m   CREATE INDEX building_parent_fkx ON citydb.building USING btree (building_parent_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.building_parent_fkx;
       citydb            postgres    false    251            h           1259    33227    building_root_fkx    INDEX     i   CREATE INDEX building_root_fkx ON citydb.building USING btree (building_root_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.building_root_fkx;
       citydb            postgres    false    251                       1259    33183    city_furn_lod1brep_fkx    INDEX     p   CREATE INDEX city_furn_lod1brep_fkx ON citydb.city_furniture USING btree (lod1_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod1brep_fkx;
       citydb            postgres    false    246                       1259    33191    city_furn_lod1impl_fkx    INDEX     x   CREATE INDEX city_furn_lod1impl_fkx ON citydb.city_furniture USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod1impl_fkx;
       citydb            postgres    false    246                       1259    36380    city_furn_lod1refpnt_spx    INDEX     e   CREATE INDEX city_furn_lod1refpnt_spx ON citydb.city_furniture USING gist (lod1_implicit_ref_point);
 ,   DROP INDEX citydb.city_furn_lod1refpnt_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    36164    city_furn_lod1terr_spx    INDEX     e   CREATE INDEX city_furn_lod1terr_spx ON citydb.city_furniture USING gist (lod1_terrain_intersection);
 *   DROP INDEX citydb.city_furn_lod1terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    246                        1259    36272    city_furn_lod1xgeom_spx    INDEX     \   CREATE INDEX city_furn_lod1xgeom_spx ON citydb.city_furniture USING gist (lod1_other_geom);
 +   DROP INDEX citydb.city_furn_lod1xgeom_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            !           1259    33184    city_furn_lod2brep_fkx    INDEX     p   CREATE INDEX city_furn_lod2brep_fkx ON citydb.city_furniture USING btree (lod2_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod2brep_fkx;
       citydb            postgres    false    246            "           1259    33192    city_furn_lod2impl_fkx    INDEX     x   CREATE INDEX city_furn_lod2impl_fkx ON citydb.city_furniture USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod2impl_fkx;
       citydb            postgres    false    246            #           1259    36407    city_furn_lod2refpnt_spx    INDEX     e   CREATE INDEX city_furn_lod2refpnt_spx ON citydb.city_furniture USING gist (lod2_implicit_ref_point);
 ,   DROP INDEX citydb.city_furn_lod2refpnt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    246            $           1259    36191    city_furn_lod2terr_spx    INDEX     e   CREATE INDEX city_furn_lod2terr_spx ON citydb.city_furniture USING gist (lod2_terrain_intersection);
 *   DROP INDEX citydb.city_furn_lod2terr_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            %           1259    36299    city_furn_lod2xgeom_spx    INDEX     \   CREATE INDEX city_furn_lod2xgeom_spx ON citydb.city_furniture USING gist (lod2_other_geom);
 +   DROP INDEX citydb.city_furn_lod2xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    246            &           1259    33185    city_furn_lod3brep_fkx    INDEX     p   CREATE INDEX city_furn_lod3brep_fkx ON citydb.city_furniture USING btree (lod3_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod3brep_fkx;
       citydb            postgres    false    246            '           1259    33193    city_furn_lod3impl_fkx    INDEX     x   CREATE INDEX city_furn_lod3impl_fkx ON citydb.city_furniture USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod3impl_fkx;
       citydb            postgres    false    246            (           1259    36434    city_furn_lod3refpnt_spx    INDEX     e   CREATE INDEX city_furn_lod3refpnt_spx ON citydb.city_furniture USING gist (lod3_implicit_ref_point);
 ,   DROP INDEX citydb.city_furn_lod3refpnt_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            )           1259    36218    city_furn_lod3terr_spx    INDEX     e   CREATE INDEX city_furn_lod3terr_spx ON citydb.city_furniture USING gist (lod3_terrain_intersection);
 *   DROP INDEX citydb.city_furn_lod3terr_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            *           1259    36326    city_furn_lod3xgeom_spx    INDEX     \   CREATE INDEX city_furn_lod3xgeom_spx ON citydb.city_furniture USING gist (lod3_other_geom);
 +   DROP INDEX citydb.city_furn_lod3xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    246            +           1259    33186    city_furn_lod4brep_fkx    INDEX     p   CREATE INDEX city_furn_lod4brep_fkx ON citydb.city_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod4brep_fkx;
       citydb            postgres    false    246            ,           1259    33194    city_furn_lod4impl_fkx    INDEX     x   CREATE INDEX city_furn_lod4impl_fkx ON citydb.city_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_lod4impl_fkx;
       citydb            postgres    false    246            -           1259    36461    city_furn_lod4refpnt_spx    INDEX     e   CREATE INDEX city_furn_lod4refpnt_spx ON citydb.city_furniture USING gist (lod4_implicit_ref_point);
 ,   DROP INDEX citydb.city_furn_lod4refpnt_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            .           1259    36245    city_furn_lod4terr_spx    INDEX     e   CREATE INDEX city_furn_lod4terr_spx ON citydb.city_furniture USING gist (lod4_terrain_intersection);
 *   DROP INDEX citydb.city_furn_lod4terr_spx;
       citydb            postgres    false    246    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            /           1259    36353    city_furn_lod4xgeom_spx    INDEX     \   CREATE INDEX city_furn_lod4xgeom_spx ON citydb.city_furniture USING gist (lod4_other_geom);
 +   DROP INDEX citydb.city_furn_lod4xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    246            0           1259    33551    city_furn_objclass_fkx    INDEX     r   CREATE INDEX city_furn_objclass_fkx ON citydb.city_furniture USING btree (objectclass_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.city_furn_objclass_fkx;
       citydb            postgres    false    246            �           1259    37822    citymodel_envelope_spx    INDEX     O   CREATE INDEX citymodel_envelope_spx ON citydb.citymodel USING gist (envelope);
 *   DROP INDEX citydb.citymodel_envelope_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    301            �           1259    33510    citymodel_inx    INDEX     U   CREATE INDEX citymodel_inx ON citydb.citymodel USING btree (gmlid, gmlid_codespace);
 !   DROP INDEX citydb.citymodel_inx;
       citydb            postgres    false    301    301            �           1259    33582    cityobj_creation_date_inx    INDEX     p   CREATE INDEX cityobj_creation_date_inx ON citydb.cityobject USING btree (creation_date) WITH (fillfactor='90');
 -   DROP INDEX citydb.cityobj_creation_date_inx;
       citydb            postgres    false    295            �           1259    33584    cityobj_last_mod_date_inx    INDEX     y   CREATE INDEX cityobj_last_mod_date_inx ON citydb.cityobject USING btree (last_modification_date) WITH (fillfactor='90');
 -   DROP INDEX citydb.cityobj_last_mod_date_inx;
       citydb            postgres    false    295            �           1259    33583    cityobj_term_date_inx    INDEX     o   CREATE INDEX cityobj_term_date_inx ON citydb.cityobject USING btree (termination_date) WITH (fillfactor='90');
 )   DROP INDEX citydb.cityobj_term_date_inx;
       citydb            postgres    false    295            �           1259    37422    cityobject_envelope_spx    INDEX     Q   CREATE INDEX cityobject_envelope_spx ON citydb.cityobject USING gist (envelope);
 +   DROP INDEX citydb.cityobject_envelope_spx;
       citydb            postgres    false    295    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33492    cityobject_inx    INDEX     n   CREATE INDEX cityobject_inx ON citydb.cityobject USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');
 "   DROP INDEX citydb.cityobject_inx;
       citydb            postgres    false    295    295            �           1259    33517    cityobject_lineage_inx    INDEX     P   CREATE INDEX cityobject_lineage_inx ON citydb.cityobject USING btree (lineage);
 *   DROP INDEX citydb.cityobject_lineage_inx;
       citydb            postgres    false    295                       1259    33169    cityobject_member_fkx    INDEX     s   CREATE INDEX cityobject_member_fkx ON citydb.cityobject_member USING btree (cityobject_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.cityobject_member_fkx;
       citydb            postgres    false    237                       1259    33170    cityobject_member_fkx1    INDEX     s   CREATE INDEX cityobject_member_fkx1 ON citydb.cityobject_member USING btree (citymodel_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.cityobject_member_fkx1;
       citydb            postgres    false    237            �           1259    33493    cityobject_objectclass_fkx    INDEX     r   CREATE INDEX cityobject_objectclass_fkx ON citydb.cityobject USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.cityobject_objectclass_fkx;
       citydb            postgres    false    295            �           1259    33515    ext_ref_cityobject_fkx    INDEX     u   CREATE INDEX ext_ref_cityobject_fkx ON citydb.external_reference USING btree (cityobject_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.ext_ref_cityobject_fkx;
       citydb            postgres    false    303            3           1259    33204    gen_object_lod0brep_fkx    INDEX     u   CREATE INDEX gen_object_lod0brep_fkx ON citydb.generic_cityobject USING btree (lod0_brep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod0brep_fkx;
       citydb            postgres    false    248            4           1259    33214    gen_object_lod0impl_fkx    INDEX     }   CREATE INDEX gen_object_lod0impl_fkx ON citydb.generic_cityobject USING btree (lod0_implicit_rep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod0impl_fkx;
       citydb            postgres    false    248            5           1259    35831    gen_object_lod0refpnt_spx    INDEX     j   CREATE INDEX gen_object_lod0refpnt_spx ON citydb.generic_cityobject USING gist (lod0_implicit_ref_point);
 -   DROP INDEX citydb.gen_object_lod0refpnt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    248            6           1259    35511    gen_object_lod0terr_spx    INDEX     j   CREATE INDEX gen_object_lod0terr_spx ON citydb.generic_cityobject USING gist (lod0_terrain_intersection);
 +   DROP INDEX citydb.gen_object_lod0terr_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            7           1259    35671    gen_object_lod0xgeom_spx    INDEX     a   CREATE INDEX gen_object_lod0xgeom_spx ON citydb.generic_cityobject USING gist (lod0_other_geom);
 ,   DROP INDEX citydb.gen_object_lod0xgeom_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            8           1259    33205    gen_object_lod1brep_fkx    INDEX     u   CREATE INDEX gen_object_lod1brep_fkx ON citydb.generic_cityobject USING btree (lod1_brep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod1brep_fkx;
       citydb            postgres    false    248            9           1259    33215    gen_object_lod1impl_fkx    INDEX     }   CREATE INDEX gen_object_lod1impl_fkx ON citydb.generic_cityobject USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod1impl_fkx;
       citydb            postgres    false    248            :           1259    35863    gen_object_lod1refpnt_spx    INDEX     j   CREATE INDEX gen_object_lod1refpnt_spx ON citydb.generic_cityobject USING gist (lod1_implicit_ref_point);
 -   DROP INDEX citydb.gen_object_lod1refpnt_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            ;           1259    35543    gen_object_lod1terr_spx    INDEX     j   CREATE INDEX gen_object_lod1terr_spx ON citydb.generic_cityobject USING gist (lod1_terrain_intersection);
 +   DROP INDEX citydb.gen_object_lod1terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    248            <           1259    35703    gen_object_lod1xgeom_spx    INDEX     a   CREATE INDEX gen_object_lod1xgeom_spx ON citydb.generic_cityobject USING gist (lod1_other_geom);
 ,   DROP INDEX citydb.gen_object_lod1xgeom_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            =           1259    33206    gen_object_lod2brep_fkx    INDEX     u   CREATE INDEX gen_object_lod2brep_fkx ON citydb.generic_cityobject USING btree (lod2_brep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod2brep_fkx;
       citydb            postgres    false    248            >           1259    33216    gen_object_lod2impl_fkx    INDEX     }   CREATE INDEX gen_object_lod2impl_fkx ON citydb.generic_cityobject USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod2impl_fkx;
       citydb            postgres    false    248            ?           1259    35895    gen_object_lod2refpnt_spx    INDEX     j   CREATE INDEX gen_object_lod2refpnt_spx ON citydb.generic_cityobject USING gist (lod2_implicit_ref_point);
 -   DROP INDEX citydb.gen_object_lod2refpnt_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            @           1259    35575    gen_object_lod2terr_spx    INDEX     j   CREATE INDEX gen_object_lod2terr_spx ON citydb.generic_cityobject USING gist (lod2_terrain_intersection);
 +   DROP INDEX citydb.gen_object_lod2terr_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            A           1259    35735    gen_object_lod2xgeom_spx    INDEX     a   CREATE INDEX gen_object_lod2xgeom_spx ON citydb.generic_cityobject USING gist (lod2_other_geom);
 ,   DROP INDEX citydb.gen_object_lod2xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    248            B           1259    33207    gen_object_lod3brep_fkx    INDEX     u   CREATE INDEX gen_object_lod3brep_fkx ON citydb.generic_cityobject USING btree (lod3_brep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod3brep_fkx;
       citydb            postgres    false    248            C           1259    33217    gen_object_lod3impl_fkx    INDEX     }   CREATE INDEX gen_object_lod3impl_fkx ON citydb.generic_cityobject USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod3impl_fkx;
       citydb            postgres    false    248            D           1259    35927    gen_object_lod3refpnt_spx    INDEX     j   CREATE INDEX gen_object_lod3refpnt_spx ON citydb.generic_cityobject USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.gen_object_lod3refpnt_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            E           1259    35607    gen_object_lod3terr_spx    INDEX     j   CREATE INDEX gen_object_lod3terr_spx ON citydb.generic_cityobject USING gist (lod3_terrain_intersection);
 +   DROP INDEX citydb.gen_object_lod3terr_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            F           1259    35767    gen_object_lod3xgeom_spx    INDEX     a   CREATE INDEX gen_object_lod3xgeom_spx ON citydb.generic_cityobject USING gist (lod3_other_geom);
 ,   DROP INDEX citydb.gen_object_lod3xgeom_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            G           1259    33208    gen_object_lod4brep_fkx    INDEX     u   CREATE INDEX gen_object_lod4brep_fkx ON citydb.generic_cityobject USING btree (lod4_brep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod4brep_fkx;
       citydb            postgres    false    248            H           1259    33218    gen_object_lod4impl_fkx    INDEX     }   CREATE INDEX gen_object_lod4impl_fkx ON citydb.generic_cityobject USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_lod4impl_fkx;
       citydb            postgres    false    248            I           1259    35959    gen_object_lod4refpnt_spx    INDEX     j   CREATE INDEX gen_object_lod4refpnt_spx ON citydb.generic_cityobject USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.gen_object_lod4refpnt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    248            J           1259    35639    gen_object_lod4terr_spx    INDEX     j   CREATE INDEX gen_object_lod4terr_spx ON citydb.generic_cityobject USING gist (lod4_terrain_intersection);
 +   DROP INDEX citydb.gen_object_lod4terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    248            K           1259    35799    gen_object_lod4xgeom_spx    INDEX     a   CREATE INDEX gen_object_lod4xgeom_spx ON citydb.generic_cityobject USING gist (lod4_other_geom);
 ,   DROP INDEX citydb.gen_object_lod4xgeom_spx;
       citydb            postgres    false    248    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            L           1259    33553    gen_object_objclass_fkx    INDEX     w   CREATE INDEX gen_object_objclass_fkx ON citydb.generic_cityobject USING btree (objectclass_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.gen_object_objclass_fkx;
       citydb            postgres    false    248                       1259    33171    general_cityobject_fkx    INDEX     q   CREATE INDEX general_cityobject_fkx ON citydb.generalization USING btree (cityobject_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.general_cityobject_fkx;
       citydb            postgres    false    239            	           1259    33172    general_generalizes_to_fkx    INDEX     y   CREATE INDEX general_generalizes_to_fkx ON citydb.generalization USING btree (generalizes_to_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.general_generalizes_to_fkx;
       citydb            postgres    false    239            �           1259    33514    genericattrib_cityobj_fkx    INDEX     ~   CREATE INDEX genericattrib_cityobj_fkx ON citydb.cityobject_genericattrib USING btree (cityobject_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.genericattrib_cityobj_fkx;
       citydb            postgres    false    302            �           1259    33513    genericattrib_geom_fkx    INDEX     �   CREATE INDEX genericattrib_geom_fkx ON citydb.cityobject_genericattrib USING btree (surface_geometry_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.genericattrib_geom_fkx;
       citydb            postgres    false    302            �           1259    33511    genericattrib_parent_fkx    INDEX     �   CREATE INDEX genericattrib_parent_fkx ON citydb.cityobject_genericattrib USING btree (parent_genattrib_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.genericattrib_parent_fkx;
       citydb            postgres    false    302            �           1259    33512    genericattrib_root_fkx    INDEX        CREATE INDEX genericattrib_root_fkx ON citydb.cityobject_genericattrib USING btree (root_genattrib_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.genericattrib_root_fkx;
       citydb            postgres    false    302            �           1259    33516    grid_coverage_raster_spx    INDEX     q   CREATE INDEX grid_coverage_raster_spx ON citydb.grid_coverage USING gist (public.st_convexhull(rasterproperty));
 ,   DROP INDEX citydb.grid_coverage_raster_spx;
       citydb            postgres    false    305    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    305    3    2    2    2    2    2    2    2    2    3    3    3                       1259    33173    group_brep_fkx    INDEX     d   CREATE INDEX group_brep_fkx ON citydb.cityobjectgroup USING btree (brep_id) WITH (fillfactor='90');
 "   DROP INDEX citydb.group_brep_fkx;
       citydb            postgres    false    241                       1259    33552    group_objectclass_fkx    INDEX     r   CREATE INDEX group_objectclass_fkx ON citydb.cityobjectgroup USING btree (objectclass_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.group_objectclass_fkx;
       citydb            postgres    false    241                       1259    33175    group_parent_cityobj_fkx    INDEX     {   CREATE INDEX group_parent_cityobj_fkx ON citydb.cityobjectgroup USING btree (parent_cityobject_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.group_parent_cityobj_fkx;
       citydb            postgres    false    241                       1259    33176    group_to_cityobject_fkx    INDEX     w   CREATE INDEX group_to_cityobject_fkx ON citydb.group_to_cityobject USING btree (cityobject_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.group_to_cityobject_fkx;
       citydb            postgres    false    242                       1259    33177    group_to_cityobject_fkx1    INDEX     }   CREATE INDEX group_to_cityobject_fkx1 ON citydb.group_to_cityobject USING btree (cityobjectgroup_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.group_to_cityobject_fkx1;
       citydb            postgres    false    242                       1259    35479    group_xgeom_spx    INDEX     P   CREATE INDEX group_xgeom_spx ON citydb.cityobjectgroup USING gist (other_geom);
 #   DROP INDEX citydb.group_xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    241            �           1259    33500    implicit_geom_brep_fkx    INDEX     w   CREATE INDEX implicit_geom_brep_fkx ON citydb.implicit_geometry USING btree (relative_brep_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.implicit_geom_brep_fkx;
       citydb            postgres    false    297            �           1259    33585    implicit_geom_inx    INDEX     x   CREATE INDEX implicit_geom_inx ON citydb.implicit_geometry USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');
 %   DROP INDEX citydb.implicit_geom_inx;
       citydb            postgres    false    297    297            �           1259    33499    implicit_geom_ref2lib_inx    INDEX     ~   CREATE INDEX implicit_geom_ref2lib_inx ON citydb.implicit_geometry USING btree (reference_to_library) WITH (fillfactor='90');
 -   DROP INDEX citydb.implicit_geom_ref2lib_inx;
       citydb            postgres    false    297            �           1259    33311    land_use_lod0msrf_fkx    INDEX     r   CREATE INDEX land_use_lod0msrf_fkx ON citydb.land_use USING btree (lod0_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_lod0msrf_fkx;
       citydb            postgres    false    270            �           1259    33312    land_use_lod1msrf_fkx    INDEX     r   CREATE INDEX land_use_lod1msrf_fkx ON citydb.land_use USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_lod1msrf_fkx;
       citydb            postgres    false    270            �           1259    33313    land_use_lod2msrf_fkx    INDEX     r   CREATE INDEX land_use_lod2msrf_fkx ON citydb.land_use USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_lod2msrf_fkx;
       citydb            postgres    false    270            �           1259    33314    land_use_lod3msrf_fkx    INDEX     r   CREATE INDEX land_use_lod3msrf_fkx ON citydb.land_use USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_lod3msrf_fkx;
       citydb            postgres    false    270            �           1259    33315    land_use_lod4msrf_fkx    INDEX     r   CREATE INDEX land_use_lod4msrf_fkx ON citydb.land_use USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_lod4msrf_fkx;
       citydb            postgres    false    270            �           1259    33554    land_use_objclass_fkx    INDEX     k   CREATE INDEX land_use_objclass_fkx ON citydb.land_use USING btree (objectclass_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.land_use_objclass_fkx;
       citydb            postgres    false    270            �           1259    33555    masspoint_rel_objclass_fkx    INDEX     x   CREATE INDEX masspoint_rel_objclass_fkx ON citydb.masspoint_relief USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.masspoint_rel_objclass_fkx;
       citydb            postgres    false    263            �           1259    36651    masspoint_relief_spx    INDEX     Y   CREATE INDEX masspoint_relief_spx ON citydb.masspoint_relief USING gist (relief_points);
 (   DROP INDEX citydb.masspoint_relief_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    263                       1259    33536    objectclass_baseclass_fkx    INDEX     p   CREATE INDEX objectclass_baseclass_fkx ON citydb.objectclass USING btree (baseclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.objectclass_baseclass_fkx;
       citydb            postgres    false    244                       1259    33178    objectclass_superclass_fkx    INDEX     r   CREATE INDEX objectclass_superclass_fkx ON citydb.objectclass USING btree (superclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.objectclass_superclass_fkx;
       citydb            postgres    false    244            �           1259    33273    open_to_them_surface_fkx    INDEX     y   CREATE INDEX open_to_them_surface_fkx ON citydb.opening_to_them_surface USING btree (opening_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.open_to_them_surface_fkx;
       citydb            postgres    false    255            �           1259    33274    open_to_them_surface_fkx1    INDEX     �   CREATE INDEX open_to_them_surface_fkx1 ON citydb.opening_to_them_surface USING btree (thematic_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.open_to_them_surface_fkx1;
       citydb            postgres    false    255            �           1259    33266    opening_address_fkx    INDEX     d   CREATE INDEX opening_address_fkx ON citydb.opening USING btree (address_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.opening_address_fkx;
       citydb            postgres    false    254            �           1259    33269    opening_lod3impl_fkx    INDEX     o   CREATE INDEX opening_lod3impl_fkx ON citydb.opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.opening_lod3impl_fkx;
       citydb            postgres    false    254            �           1259    33267    opening_lod3msrf_fkx    INDEX     p   CREATE INDEX opening_lod3msrf_fkx ON citydb.opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.opening_lod3msrf_fkx;
       citydb            postgres    false    254            �           1259    36123    opening_lod3refpt_spx    INDEX     [   CREATE INDEX opening_lod3refpt_spx ON citydb.opening USING gist (lod3_implicit_ref_point);
 )   DROP INDEX citydb.opening_lod3refpt_spx;
       citydb            postgres    false    254    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33270    opening_lod4impl_fkx    INDEX     o   CREATE INDEX opening_lod4impl_fkx ON citydb.opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.opening_lod4impl_fkx;
       citydb            postgres    false    254            �           1259    33268    opening_lod4msrf_fkx    INDEX     p   CREATE INDEX opening_lod4msrf_fkx ON citydb.opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.opening_lod4msrf_fkx;
       citydb            postgres    false    254            �           1259    36137    opening_lod4refpt_spx    INDEX     [   CREATE INDEX opening_lod4refpt_spx ON citydb.opening USING gist (lod4_implicit_ref_point);
 )   DROP INDEX citydb.opening_lod4refpt_spx;
       citydb            postgres    false    254    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33265    opening_objectclass_fkx    INDEX     l   CREATE INDEX opening_objectclass_fkx ON citydb.opening USING btree (objectclass_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.opening_objectclass_fkx;
       citydb            postgres    false    254            �           1259    33320    plant_cover_lod1msolid_fkx    INDEX     x   CREATE INDEX plant_cover_lod1msolid_fkx ON citydb.plant_cover USING btree (lod1_multi_solid_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.plant_cover_lod1msolid_fkx;
       citydb            postgres    false    271            �           1259    33316    plant_cover_lod1msrf_fkx    INDEX     x   CREATE INDEX plant_cover_lod1msrf_fkx ON citydb.plant_cover USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.plant_cover_lod1msrf_fkx;
       citydb            postgres    false    271            �           1259    33321    plant_cover_lod2msolid_fkx    INDEX     x   CREATE INDEX plant_cover_lod2msolid_fkx ON citydb.plant_cover USING btree (lod2_multi_solid_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.plant_cover_lod2msolid_fkx;
       citydb            postgres    false    271            �           1259    33317    plant_cover_lod2msrf_fkx    INDEX     x   CREATE INDEX plant_cover_lod2msrf_fkx ON citydb.plant_cover USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.plant_cover_lod2msrf_fkx;
       citydb            postgres    false    271            �           1259    33322    plant_cover_lod3msolid_fkx    INDEX     x   CREATE INDEX plant_cover_lod3msolid_fkx ON citydb.plant_cover USING btree (lod3_multi_solid_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.plant_cover_lod3msolid_fkx;
       citydb            postgres    false    271            �           1259    33318    plant_cover_lod3msrf_fkx    INDEX     x   CREATE INDEX plant_cover_lod3msrf_fkx ON citydb.plant_cover USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.plant_cover_lod3msrf_fkx;
       citydb            postgres    false    271            �           1259    33323    plant_cover_lod4msolid_fkx    INDEX     x   CREATE INDEX plant_cover_lod4msolid_fkx ON citydb.plant_cover USING btree (lod4_multi_solid_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.plant_cover_lod4msolid_fkx;
       citydb            postgres    false    271            �           1259    33319    plant_cover_lod4msrf_fkx    INDEX     x   CREATE INDEX plant_cover_lod4msrf_fkx ON citydb.plant_cover USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.plant_cover_lod4msrf_fkx;
       citydb            postgres    false    271            �           1259    33556    plant_cover_objclass_fkx    INDEX     q   CREATE INDEX plant_cover_objclass_fkx ON citydb.plant_cover USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.plant_cover_objclass_fkx;
       citydb            postgres    false    271                       1259    33354    raster_relief_coverage_fkx    INDEX     r   CREATE INDEX raster_relief_coverage_fkx ON citydb.raster_relief USING btree (coverage_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.raster_relief_coverage_fkx;
       citydb            postgres    false    276                       1259    33557    raster_relief_objclass_fkx    INDEX     u   CREATE INDEX raster_relief_objclass_fkx ON citydb.raster_relief USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.raster_relief_objclass_fkx;
       citydb            postgres    false    276            �           1259    33294    rel_feat_to_rel_comp_fkx    INDEX     �   CREATE INDEX rel_feat_to_rel_comp_fkx ON citydb.relief_feat_to_rel_comp USING btree (relief_component_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.rel_feat_to_rel_comp_fkx;
       citydb            postgres    false    265            �           1259    33295    rel_feat_to_rel_comp_fkx1    INDEX     �   CREATE INDEX rel_feat_to_rel_comp_fkx1 ON citydb.relief_feat_to_rel_comp USING btree (relief_feature_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.rel_feat_to_rel_comp_fkx1;
       citydb            postgres    false    265            �           1259    37814    relief_comp_extent_spx    INDEX     T   CREATE INDEX relief_comp_extent_spx ON citydb.relief_component USING gist (extent);
 *   DROP INDEX citydb.relief_comp_extent_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    264            �           1259    33292    relief_comp_objclass_fkx    INDEX     v   CREATE INDEX relief_comp_objclass_fkx ON citydb.relief_component USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.relief_comp_objclass_fkx;
       citydb            postgres    false    264            �           1259    33558    relief_feat_objclass_fkx    INDEX     t   CREATE INDEX relief_feat_objclass_fkx ON citydb.relief_feature USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.relief_feat_objclass_fkx;
       citydb            postgres    false    266            �           1259    33275    room_building_fkx    INDEX     `   CREATE INDEX room_building_fkx ON citydb.room USING btree (building_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.room_building_fkx;
       citydb            postgres    false    256            �           1259    33276    room_lod4msrf_fkx    INDEX     j   CREATE INDEX room_lod4msrf_fkx ON citydb.room USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.room_lod4msrf_fkx;
       citydb            postgres    false    256            �           1259    33277    room_lod4solid_fkx    INDEX     c   CREATE INDEX room_lod4solid_fkx ON citydb.room USING btree (lod4_solid_id) WITH (fillfactor='90');
 &   DROP INDEX citydb.room_lod4solid_fkx;
       citydb            postgres    false    256            �           1259    33559    room_objectclass_fkx    INDEX     f   CREATE INDEX room_objectclass_fkx ON citydb.room USING btree (objectclass_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.room_objectclass_fkx;
       citydb            postgres    false    256            �           1259    33542    schema_referencing_fkx1    INDEX     v   CREATE INDEX schema_referencing_fkx1 ON citydb.schema_referencing USING btree (referenced_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.schema_referencing_fkx1;
       citydb            postgres    false    310            �           1259    33543    schema_referencing_fkx2    INDEX     w   CREATE INDEX schema_referencing_fkx2 ON citydb.schema_referencing USING btree (referencing_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.schema_referencing_fkx2;
       citydb            postgres    false    310            �           1259    33534    schema_to_objectclass_fkx1    INDEX     x   CREATE INDEX schema_to_objectclass_fkx1 ON citydb.schema_to_objectclass USING btree (schema_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.schema_to_objectclass_fkx1;
       citydb            postgres    false    309            �           1259    33535    schema_to_objectclass_fkx2    INDEX     }   CREATE INDEX schema_to_objectclass_fkx2 ON citydb.schema_to_objectclass USING btree (objectclass_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.schema_to_objectclass_fkx2;
       citydb            postgres    false    309            �           1259    33324    sol_veg_obj_lod1brep_fkx    INDEX     {   CREATE INDEX sol_veg_obj_lod1brep_fkx ON citydb.solitary_vegetat_object USING btree (lod1_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod1brep_fkx;
       citydb            postgres    false    272            �           1259    33332    sol_veg_obj_lod1impl_fkx    INDEX     �   CREATE INDEX sol_veg_obj_lod1impl_fkx ON citydb.solitary_vegetat_object USING btree (lod1_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod1impl_fkx;
       citydb            postgres    false    272            �           1259    35370    sol_veg_obj_lod1refpt_spx    INDEX     o   CREATE INDEX sol_veg_obj_lod1refpt_spx ON citydb.solitary_vegetat_object USING gist (lod1_implicit_ref_point);
 -   DROP INDEX citydb.sol_veg_obj_lod1refpt_spx;
       citydb            postgres    false    272    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    35278    sol_veg_obj_lod1xgeom_spx    INDEX     g   CREATE INDEX sol_veg_obj_lod1xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod1_other_geom);
 -   DROP INDEX citydb.sol_veg_obj_lod1xgeom_spx;
       citydb            postgres    false    272    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33325    sol_veg_obj_lod2brep_fkx    INDEX     {   CREATE INDEX sol_veg_obj_lod2brep_fkx ON citydb.solitary_vegetat_object USING btree (lod2_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod2brep_fkx;
       citydb            postgres    false    272            �           1259    33333    sol_veg_obj_lod2impl_fkx    INDEX     �   CREATE INDEX sol_veg_obj_lod2impl_fkx ON citydb.solitary_vegetat_object USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod2impl_fkx;
       citydb            postgres    false    272            �           1259    35393    sol_veg_obj_lod2refpt_spx    INDEX     o   CREATE INDEX sol_veg_obj_lod2refpt_spx ON citydb.solitary_vegetat_object USING gist (lod2_implicit_ref_point);
 -   DROP INDEX citydb.sol_veg_obj_lod2refpt_spx;
       citydb            postgres    false    272    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    35301    sol_veg_obj_lod2xgeom_spx    INDEX     g   CREATE INDEX sol_veg_obj_lod2xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod2_other_geom);
 -   DROP INDEX citydb.sol_veg_obj_lod2xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    272            �           1259    33326    sol_veg_obj_lod3brep_fkx    INDEX     {   CREATE INDEX sol_veg_obj_lod3brep_fkx ON citydb.solitary_vegetat_object USING btree (lod3_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod3brep_fkx;
       citydb            postgres    false    272            �           1259    33334    sol_veg_obj_lod3impl_fkx    INDEX     �   CREATE INDEX sol_veg_obj_lod3impl_fkx ON citydb.solitary_vegetat_object USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod3impl_fkx;
       citydb            postgres    false    272            �           1259    35416    sol_veg_obj_lod3refpt_spx    INDEX     o   CREATE INDEX sol_veg_obj_lod3refpt_spx ON citydb.solitary_vegetat_object USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.sol_veg_obj_lod3refpt_spx;
       citydb            postgres    false    272    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    35324    sol_veg_obj_lod3xgeom_spx    INDEX     g   CREATE INDEX sol_veg_obj_lod3xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod3_other_geom);
 -   DROP INDEX citydb.sol_veg_obj_lod3xgeom_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    272            �           1259    33327    sol_veg_obj_lod4brep_fkx    INDEX     {   CREATE INDEX sol_veg_obj_lod4brep_fkx ON citydb.solitary_vegetat_object USING btree (lod4_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod4brep_fkx;
       citydb            postgres    false    272            �           1259    33335    sol_veg_obj_lod4impl_fkx    INDEX     �   CREATE INDEX sol_veg_obj_lod4impl_fkx ON citydb.solitary_vegetat_object USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_lod4impl_fkx;
       citydb            postgres    false    272            �           1259    35439    sol_veg_obj_lod4refpt_spx    INDEX     o   CREATE INDEX sol_veg_obj_lod4refpt_spx ON citydb.solitary_vegetat_object USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.sol_veg_obj_lod4refpt_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    272            �           1259    35347    sol_veg_obj_lod4xgeom_spx    INDEX     g   CREATE INDEX sol_veg_obj_lod4xgeom_spx ON citydb.solitary_vegetat_object USING gist (lod4_other_geom);
 -   DROP INDEX citydb.sol_veg_obj_lod4xgeom_spx;
       citydb            postgres    false    272    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33560    sol_veg_obj_objclass_fkx    INDEX     }   CREATE INDEX sol_veg_obj_objclass_fkx ON citydb.solitary_vegetat_object USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.sol_veg_obj_objclass_fkx;
       citydb            postgres    false    272            �           1259    33507    surface_data_inx    INDEX     r   CREATE INDEX surface_data_inx ON citydb.surface_data USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');
 $   DROP INDEX citydb.surface_data_inx;
       citydb            postgres    false    300    300            �           1259    33574    surface_data_objclass_fkx    INDEX     \   CREATE INDEX surface_data_objclass_fkx ON citydb.surface_data USING btree (objectclass_id);
 -   DROP INDEX citydb.surface_data_objclass_fkx;
       citydb            postgres    false    300            �           1259    37796    surface_data_spx    INDEX     V   CREATE INDEX surface_data_spx ON citydb.surface_data USING gist (gt_reference_point);
 $   DROP INDEX citydb.surface_data_spx;
       citydb            postgres    false    300    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33509    surface_data_tex_image_fkx    INDEX     [   CREATE INDEX surface_data_tex_image_fkx ON citydb.surface_data USING btree (tex_image_id);
 .   DROP INDEX citydb.surface_data_tex_image_fkx;
       citydb            postgres    false    300            �           1259    33506    surface_geom_cityobj_fkx    INDEX     u   CREATE INDEX surface_geom_cityobj_fkx ON citydb.surface_geometry USING btree (cityobject_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.surface_geom_cityobj_fkx;
       citydb            postgres    false    298            �           1259    33501    surface_geom_inx    INDEX     v   CREATE INDEX surface_geom_inx ON citydb.surface_geometry USING btree (gmlid, gmlid_codespace) WITH (fillfactor='90');
 $   DROP INDEX citydb.surface_geom_inx;
       citydb            postgres    false    298    298            �           1259    33502    surface_geom_parent_fkx    INDEX     p   CREATE INDEX surface_geom_parent_fkx ON citydb.surface_geometry USING btree (parent_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.surface_geom_parent_fkx;
       citydb            postgres    false    298            �           1259    33503    surface_geom_root_fkx    INDEX     l   CREATE INDEX surface_geom_root_fkx ON citydb.surface_geometry USING btree (root_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.surface_geom_root_fkx;
       citydb            postgres    false    298            �           1259    37389    surface_geom_solid_spx    INDEX     \   CREATE INDEX surface_geom_solid_spx ON citydb.surface_geometry USING gist (solid_geometry);
 *   DROP INDEX citydb.surface_geom_solid_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    298            �           1259    37401    surface_geom_spx    INDEX     P   CREATE INDEX surface_geom_spx ON citydb.surface_geometry USING gist (geometry);
 $   DROP INDEX citydb.surface_geom_spx;
       citydb            postgres    false    298    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33285    texparam_geom_fkx    INDEX     p   CREATE INDEX texparam_geom_fkx ON citydb.textureparam USING btree (surface_geometry_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.texparam_geom_fkx;
       citydb            postgres    false    260            �           1259    33286    texparam_surface_data_fkx    INDEX     t   CREATE INDEX texparam_surface_data_fkx ON citydb.textureparam USING btree (surface_data_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.texparam_surface_data_fkx;
       citydb            postgres    false    260            �           1259    33281    them_surface_bldg_inst_fkx    INDEX     �   CREATE INDEX them_surface_bldg_inst_fkx ON citydb.thematic_surface USING btree (building_installation_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.them_surface_bldg_inst_fkx;
       citydb            postgres    false    257            �           1259    33279    them_surface_building_fkx    INDEX     t   CREATE INDEX them_surface_building_fkx ON citydb.thematic_surface USING btree (building_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.them_surface_building_fkx;
       citydb            postgres    false    257            �           1259    33282    them_surface_lod2msrf_fkx    INDEX     ~   CREATE INDEX them_surface_lod2msrf_fkx ON citydb.thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.them_surface_lod2msrf_fkx;
       citydb            postgres    false    257            �           1259    33283    them_surface_lod3msrf_fkx    INDEX     ~   CREATE INDEX them_surface_lod3msrf_fkx ON citydb.thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.them_surface_lod3msrf_fkx;
       citydb            postgres    false    257            �           1259    33284    them_surface_lod4msrf_fkx    INDEX     ~   CREATE INDEX them_surface_lod4msrf_fkx ON citydb.thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.them_surface_lod4msrf_fkx;
       citydb            postgres    false    257            �           1259    33278    them_surface_objclass_fkx    INDEX     w   CREATE INDEX them_surface_objclass_fkx ON citydb.thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.them_surface_objclass_fkx;
       citydb            postgres    false    257            �           1259    33280    them_surface_room_fkx    INDEX     l   CREATE INDEX them_surface_room_fkx ON citydb.thematic_surface USING btree (room_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.them_surface_room_fkx;
       citydb            postgres    false    257            �           1259    36691    tin_relief_break_spx    INDEX     Q   CREATE INDEX tin_relief_break_spx ON citydb.tin_relief USING gist (break_lines);
 (   DROP INDEX citydb.tin_relief_break_spx;
       citydb            postgres    false    267    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    36702    tin_relief_crtlpts_spx    INDEX     V   CREATE INDEX tin_relief_crtlpts_spx ON citydb.tin_relief USING gist (control_points);
 *   DROP INDEX citydb.tin_relief_crtlpts_spx;
       citydb            postgres    false    267    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33296    tin_relief_geom_fkx    INDEX     p   CREATE INDEX tin_relief_geom_fkx ON citydb.tin_relief USING btree (surface_geometry_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.tin_relief_geom_fkx;
       citydb            postgres    false    267            �           1259    33561    tin_relief_objclass_fkx    INDEX     o   CREATE INDEX tin_relief_objclass_fkx ON citydb.tin_relief USING btree (objectclass_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.tin_relief_objclass_fkx;
       citydb            postgres    false    267            �           1259    36680    tin_relief_stop_spx    INDEX     O   CREATE INDEX tin_relief_stop_spx ON citydb.tin_relief USING gist (stop_lines);
 '   DROP INDEX citydb.tin_relief_stop_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    267            �           1259    33307    traffic_area_lod2msrf_fkx    INDEX     z   CREATE INDEX traffic_area_lod2msrf_fkx ON citydb.traffic_area USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.traffic_area_lod2msrf_fkx;
       citydb            postgres    false    269            �           1259    33308    traffic_area_lod3msrf_fkx    INDEX     z   CREATE INDEX traffic_area_lod3msrf_fkx ON citydb.traffic_area USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.traffic_area_lod3msrf_fkx;
       citydb            postgres    false    269            �           1259    33309    traffic_area_lod4msrf_fkx    INDEX     z   CREATE INDEX traffic_area_lod4msrf_fkx ON citydb.traffic_area USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.traffic_area_lod4msrf_fkx;
       citydb            postgres    false    269            �           1259    33306    traffic_area_objclass_fkx    INDEX     \   CREATE INDEX traffic_area_objclass_fkx ON citydb.traffic_area USING btree (objectclass_id);
 -   DROP INDEX citydb.traffic_area_objclass_fkx;
       citydb            postgres    false    269            �           1259    33310    traffic_area_trancmplx_fkx    INDEX        CREATE INDEX traffic_area_trancmplx_fkx ON citydb.traffic_area USING btree (transportation_complex_id) WITH (fillfactor='90');
 .   DROP INDEX citydb.traffic_area_trancmplx_fkx;
       citydb            postgres    false    269            �           1259    36714    tran_complex_lod0net_spx    INDEX     b   CREATE INDEX tran_complex_lod0net_spx ON citydb.transportation_complex USING gist (lod0_network);
 ,   DROP INDEX citydb.tran_complex_lod0net_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    268            �           1259    33302    tran_complex_lod1msrf_fkx    INDEX     �   CREATE INDEX tran_complex_lod1msrf_fkx ON citydb.transportation_complex USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tran_complex_lod1msrf_fkx;
       citydb            postgres    false    268            �           1259    33303    tran_complex_lod2msrf_fkx    INDEX     �   CREATE INDEX tran_complex_lod2msrf_fkx ON citydb.transportation_complex USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tran_complex_lod2msrf_fkx;
       citydb            postgres    false    268            �           1259    33304    tran_complex_lod3msrf_fkx    INDEX     �   CREATE INDEX tran_complex_lod3msrf_fkx ON citydb.transportation_complex USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tran_complex_lod3msrf_fkx;
       citydb            postgres    false    268            �           1259    33305    tran_complex_lod4msrf_fkx    INDEX     �   CREATE INDEX tran_complex_lod4msrf_fkx ON citydb.transportation_complex USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tran_complex_lod4msrf_fkx;
       citydb            postgres    false    268            �           1259    33300    tran_complex_objclass_fkx    INDEX     }   CREATE INDEX tran_complex_objclass_fkx ON citydb.transportation_complex USING btree (objectclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tran_complex_objclass_fkx;
       citydb            postgres    false    268            (           1259    33375    tun_hspace_lod4msrf_fkx    INDEX        CREATE INDEX tun_hspace_lod4msrf_fkx ON citydb.tunnel_hollow_space USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.tun_hspace_lod4msrf_fkx;
       citydb            postgres    false    279            )           1259    33376    tun_hspace_lod4solid_fkx    INDEX     x   CREATE INDEX tun_hspace_lod4solid_fkx ON citydb.tunnel_hollow_space USING btree (lod4_solid_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tun_hspace_lod4solid_fkx;
       citydb            postgres    false    279            *           1259    33564    tun_hspace_objclass_fkx    INDEX     x   CREATE INDEX tun_hspace_objclass_fkx ON citydb.tunnel_hollow_space USING btree (objectclass_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.tun_hspace_objclass_fkx;
       citydb            postgres    false    279            +           1259    33374    tun_hspace_tunnel_fkx    INDEX     q   CREATE INDEX tun_hspace_tunnel_fkx ON citydb.tunnel_hollow_space USING btree (tunnel_id) WITH (fillfactor='90');
 )   DROP INDEX citydb.tun_hspace_tunnel_fkx;
       citydb            postgres    false    279            $           1259    33372    tun_open_to_them_srf_fkx    INDEX     �   CREATE INDEX tun_open_to_them_srf_fkx ON citydb.tunnel_open_to_them_srf USING btree (tunnel_opening_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tun_open_to_them_srf_fkx;
       citydb            postgres    false    278            %           1259    33373    tun_open_to_them_srf_fkx1    INDEX     �   CREATE INDEX tun_open_to_them_srf_fkx1 ON citydb.tunnel_open_to_them_srf USING btree (tunnel_thematic_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_open_to_them_srf_fkx1;
       citydb            postgres    false    278            .           1259    33379    tun_them_srf_hspace_fkx    INDEX     �   CREATE INDEX tun_them_srf_hspace_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.tun_them_srf_hspace_fkx;
       citydb            postgres    false    280            /           1259    33381    tun_them_srf_lod2msrf_fkx    INDEX     �   CREATE INDEX tun_them_srf_lod2msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_them_srf_lod2msrf_fkx;
       citydb            postgres    false    280            0           1259    33382    tun_them_srf_lod3msrf_fkx    INDEX     �   CREATE INDEX tun_them_srf_lod3msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_them_srf_lod3msrf_fkx;
       citydb            postgres    false    280            1           1259    33383    tun_them_srf_lod4msrf_fkx    INDEX     �   CREATE INDEX tun_them_srf_lod4msrf_fkx ON citydb.tunnel_thematic_surface USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_them_srf_lod4msrf_fkx;
       citydb            postgres    false    280            2           1259    33377    tun_them_srf_objclass_fkx    INDEX     ~   CREATE INDEX tun_them_srf_objclass_fkx ON citydb.tunnel_thematic_surface USING btree (objectclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_them_srf_objclass_fkx;
       citydb            postgres    false    280            3           1259    33380    tun_them_srf_tun_inst_fkx    INDEX     �   CREATE INDEX tun_them_srf_tun_inst_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_installation_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.tun_them_srf_tun_inst_fkx;
       citydb            postgres    false    280            4           1259    33378    tun_them_srf_tunnel_fkx    INDEX     w   CREATE INDEX tun_them_srf_tunnel_fkx ON citydb.tunnel_thematic_surface USING btree (tunnel_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.tun_them_srf_tunnel_fkx;
       citydb            postgres    false    280            Q           1259    33406    tunnel_furn_hspace_fkx    INDEX     |   CREATE INDEX tunnel_furn_hspace_fkx ON citydb.tunnel_furniture USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.tunnel_furn_hspace_fkx;
       citydb            postgres    false    284            R           1259    33407    tunnel_furn_lod4brep_fkx    INDEX     t   CREATE INDEX tunnel_furn_lod4brep_fkx ON citydb.tunnel_furniture USING btree (lod4_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_furn_lod4brep_fkx;
       citydb            postgres    false    284            S           1259    33409    tunnel_furn_lod4impl_fkx    INDEX     |   CREATE INDEX tunnel_furn_lod4impl_fkx ON citydb.tunnel_furniture USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_furn_lod4impl_fkx;
       citydb            postgres    false    284            T           1259    37058    tunnel_furn_lod4refpt_spx    INDEX     h   CREATE INDEX tunnel_furn_lod4refpt_spx ON citydb.tunnel_furniture USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_furn_lod4refpt_spx;
       citydb            postgres    false    284    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            U           1259    37046    tunnel_furn_lod4xgeom_spx    INDEX     `   CREATE INDEX tunnel_furn_lod4xgeom_spx ON citydb.tunnel_furniture USING gist (lod4_other_geom);
 -   DROP INDEX citydb.tunnel_furn_lod4xgeom_spx;
       citydb            postgres    false    284    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            V           1259    33563    tunnel_furn_objclass_fkx    INDEX     v   CREATE INDEX tunnel_furn_objclass_fkx ON citydb.tunnel_furniture USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_furn_objclass_fkx;
       citydb            postgres    false    284            @           1259    33393    tunnel_inst_hspace_fkx    INDEX        CREATE INDEX tunnel_inst_hspace_fkx ON citydb.tunnel_installation USING btree (tunnel_hollow_space_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.tunnel_inst_hspace_fkx;
       citydb            postgres    false    283            A           1259    33394    tunnel_inst_lod2brep_fkx    INDEX     w   CREATE INDEX tunnel_inst_lod2brep_fkx ON citydb.tunnel_installation USING btree (lod2_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod2brep_fkx;
       citydb            postgres    false    283            B           1259    33400    tunnel_inst_lod2impl_fkx    INDEX        CREATE INDEX tunnel_inst_lod2impl_fkx ON citydb.tunnel_installation USING btree (lod2_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod2impl_fkx;
       citydb            postgres    false    283            C           1259    36992    tunnel_inst_lod2refpt_spx    INDEX     k   CREATE INDEX tunnel_inst_lod2refpt_spx ON citydb.tunnel_installation USING gist (lod2_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_inst_lod2refpt_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            D           1259    36929    tunnel_inst_lod2xgeom_spx    INDEX     c   CREATE INDEX tunnel_inst_lod2xgeom_spx ON citydb.tunnel_installation USING gist (lod2_other_geom);
 -   DROP INDEX citydb.tunnel_inst_lod2xgeom_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            E           1259    33395    tunnel_inst_lod3brep_fkx    INDEX     w   CREATE INDEX tunnel_inst_lod3brep_fkx ON citydb.tunnel_installation USING btree (lod3_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod3brep_fkx;
       citydb            postgres    false    283            F           1259    33401    tunnel_inst_lod3impl_fkx    INDEX        CREATE INDEX tunnel_inst_lod3impl_fkx ON citydb.tunnel_installation USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod3impl_fkx;
       citydb            postgres    false    283            G           1259    37013    tunnel_inst_lod3refpt_spx    INDEX     k   CREATE INDEX tunnel_inst_lod3refpt_spx ON citydb.tunnel_installation USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_inst_lod3refpt_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            H           1259    36950    tunnel_inst_lod3xgeom_spx    INDEX     c   CREATE INDEX tunnel_inst_lod3xgeom_spx ON citydb.tunnel_installation USING gist (lod3_other_geom);
 -   DROP INDEX citydb.tunnel_inst_lod3xgeom_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            I           1259    33396    tunnel_inst_lod4brep_fkx    INDEX     w   CREATE INDEX tunnel_inst_lod4brep_fkx ON citydb.tunnel_installation USING btree (lod4_brep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod4brep_fkx;
       citydb            postgres    false    283            J           1259    33402    tunnel_inst_lod4impl_fkx    INDEX        CREATE INDEX tunnel_inst_lod4impl_fkx ON citydb.tunnel_installation USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_inst_lod4impl_fkx;
       citydb            postgres    false    283            K           1259    37034    tunnel_inst_lod4refpt_spx    INDEX     k   CREATE INDEX tunnel_inst_lod4refpt_spx ON citydb.tunnel_installation USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_inst_lod4refpt_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            L           1259    36971    tunnel_inst_lod4xgeom_spx    INDEX     c   CREATE INDEX tunnel_inst_lod4xgeom_spx ON citydb.tunnel_installation USING gist (lod4_other_geom);
 -   DROP INDEX citydb.tunnel_inst_lod4xgeom_spx;
       citydb            postgres    false    283    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            M           1259    33391    tunnel_inst_objclass_fkx    INDEX     b   CREATE INDEX tunnel_inst_objclass_fkx ON citydb.tunnel_installation USING btree (objectclass_id);
 ,   DROP INDEX citydb.tunnel_inst_objclass_fkx;
       citydb            postgres    false    283            N           1259    33392    tunnel_inst_tunnel_fkx    INDEX     r   CREATE INDEX tunnel_inst_tunnel_fkx ON citydb.tunnel_installation USING btree (tunnel_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.tunnel_inst_tunnel_fkx;
       citydb            postgres    false    283                       1259    33364    tunnel_lod1msrf_fkx    INDEX     n   CREATE INDEX tunnel_lod1msrf_fkx ON citydb.tunnel USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.tunnel_lod1msrf_fkx;
       citydb            postgres    false    277                       1259    33368    tunnel_lod1solid_fkx    INDEX     g   CREATE INDEX tunnel_lod1solid_fkx ON citydb.tunnel USING btree (lod1_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.tunnel_lod1solid_fkx;
       citydb            postgres    false    277                       1259    36738    tunnel_lod1terr_spx    INDEX     Z   CREATE INDEX tunnel_lod1terr_spx ON citydb.tunnel USING gist (lod1_terrain_intersection);
 '   DROP INDEX citydb.tunnel_lod1terr_spx;
       citydb            postgres    false    277    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    36834    tunnel_lod2curve_spx    INDEX     R   CREATE INDEX tunnel_lod2curve_spx ON citydb.tunnel USING gist (lod2_multi_curve);
 (   DROP INDEX citydb.tunnel_lod2curve_spx;
       citydb            postgres    false    277    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    33365    tunnel_lod2msrf_fkx    INDEX     n   CREATE INDEX tunnel_lod2msrf_fkx ON citydb.tunnel USING btree (lod2_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.tunnel_lod2msrf_fkx;
       citydb            postgres    false    277                       1259    33369    tunnel_lod2solid_fkx    INDEX     g   CREATE INDEX tunnel_lod2solid_fkx ON citydb.tunnel USING btree (lod2_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.tunnel_lod2solid_fkx;
       citydb            postgres    false    277                       1259    36762    tunnel_lod2terr_spx    INDEX     Z   CREATE INDEX tunnel_lod2terr_spx ON citydb.tunnel USING gist (lod2_terrain_intersection);
 '   DROP INDEX citydb.tunnel_lod2terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    277                       1259    36858    tunnel_lod3curve_spx    INDEX     R   CREATE INDEX tunnel_lod3curve_spx ON citydb.tunnel USING gist (lod3_multi_curve);
 (   DROP INDEX citydb.tunnel_lod3curve_spx;
       citydb            postgres    false    277    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    33366    tunnel_lod3msrf_fkx    INDEX     n   CREATE INDEX tunnel_lod3msrf_fkx ON citydb.tunnel USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.tunnel_lod3msrf_fkx;
       citydb            postgres    false    277                       1259    33370    tunnel_lod3solid_fkx    INDEX     g   CREATE INDEX tunnel_lod3solid_fkx ON citydb.tunnel USING btree (lod3_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.tunnel_lod3solid_fkx;
       citydb            postgres    false    277                       1259    36786    tunnel_lod3terr_spx    INDEX     Z   CREATE INDEX tunnel_lod3terr_spx ON citydb.tunnel USING gist (lod3_terrain_intersection);
 '   DROP INDEX citydb.tunnel_lod3terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    277                       1259    36882    tunnel_lod4curve_spx    INDEX     R   CREATE INDEX tunnel_lod4curve_spx ON citydb.tunnel USING gist (lod4_multi_curve);
 (   DROP INDEX citydb.tunnel_lod4curve_spx;
       citydb            postgres    false    277    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2                       1259    33367    tunnel_lod4msrf_fkx    INDEX     n   CREATE INDEX tunnel_lod4msrf_fkx ON citydb.tunnel USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 '   DROP INDEX citydb.tunnel_lod4msrf_fkx;
       citydb            postgres    false    277                       1259    33371    tunnel_lod4solid_fkx    INDEX     g   CREATE INDEX tunnel_lod4solid_fkx ON citydb.tunnel USING btree (lod4_solid_id) WITH (fillfactor='90');
 (   DROP INDEX citydb.tunnel_lod4solid_fkx;
       citydb            postgres    false    277                       1259    36810    tunnel_lod4terr_spx    INDEX     Z   CREATE INDEX tunnel_lod4terr_spx ON citydb.tunnel USING gist (lod4_terrain_intersection);
 '   DROP INDEX citydb.tunnel_lod4terr_spx;
       citydb            postgres    false    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    277                       1259    33562    tunnel_objectclass_fkx    INDEX     j   CREATE INDEX tunnel_objectclass_fkx ON citydb.tunnel USING btree (objectclass_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.tunnel_objectclass_fkx;
       citydb            postgres    false    277            7           1259    33387    tunnel_open_lod3impl_fkx    INDEX     z   CREATE INDEX tunnel_open_lod3impl_fkx ON citydb.tunnel_opening USING btree (lod3_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_open_lod3impl_fkx;
       citydb            postgres    false    282            8           1259    33385    tunnel_open_lod3msrf_fkx    INDEX     {   CREATE INDEX tunnel_open_lod3msrf_fkx ON citydb.tunnel_opening USING btree (lod3_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_open_lod3msrf_fkx;
       citydb            postgres    false    282            9           1259    36895    tunnel_open_lod3refpt_spx    INDEX     f   CREATE INDEX tunnel_open_lod3refpt_spx ON citydb.tunnel_opening USING gist (lod3_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_open_lod3refpt_spx;
       citydb            postgres    false    282    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            :           1259    33388    tunnel_open_lod4impl_fkx    INDEX     z   CREATE INDEX tunnel_open_lod4impl_fkx ON citydb.tunnel_opening USING btree (lod4_implicit_rep_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_open_lod4impl_fkx;
       citydb            postgres    false    282            ;           1259    33386    tunnel_open_lod4msrf_fkx    INDEX     {   CREATE INDEX tunnel_open_lod4msrf_fkx ON citydb.tunnel_opening USING btree (lod4_multi_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_open_lod4msrf_fkx;
       citydb            postgres    false    282            <           1259    36908    tunnel_open_lod4refpt_spx    INDEX     f   CREATE INDEX tunnel_open_lod4refpt_spx ON citydb.tunnel_opening USING gist (lod4_implicit_ref_point);
 -   DROP INDEX citydb.tunnel_open_lod4refpt_spx;
       citydb            postgres    false    282    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            =           1259    33384    tunnel_open_objclass_fkx    INDEX     t   CREATE INDEX tunnel_open_objclass_fkx ON citydb.tunnel_opening USING btree (objectclass_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.tunnel_open_objclass_fkx;
       citydb            postgres    false    282                        1259    33355    tunnel_parent_fkx    INDEX     g   CREATE INDEX tunnel_parent_fkx ON citydb.tunnel USING btree (tunnel_parent_id) WITH (fillfactor='90');
 %   DROP INDEX citydb.tunnel_parent_fkx;
       citydb            postgres    false    277            #           1259    33356    tunnel_root_fkx    INDEX     c   CREATE INDEX tunnel_root_fkx ON citydb.tunnel USING btree (tunnel_root_id) WITH (fillfactor='90');
 #   DROP INDEX citydb.tunnel_root_fkx;
       citydb            postgres    false    277                       1259    33351    waterbnd_srf_lod2srf_fkx    INDEX     |   CREATE INDEX waterbnd_srf_lod2srf_fkx ON citydb.waterboundary_surface USING btree (lod2_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.waterbnd_srf_lod2srf_fkx;
       citydb            postgres    false    275                       1259    33352    waterbnd_srf_lod3srf_fkx    INDEX     |   CREATE INDEX waterbnd_srf_lod3srf_fkx ON citydb.waterboundary_surface USING btree (lod3_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.waterbnd_srf_lod3srf_fkx;
       citydb            postgres    false    275                       1259    33353    waterbnd_srf_lod4srf_fkx    INDEX     |   CREATE INDEX waterbnd_srf_lod4srf_fkx ON citydb.waterboundary_surface USING btree (lod4_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.waterbnd_srf_lod4srf_fkx;
       citydb            postgres    false    275            	           1259    33350    waterbnd_srf_objclass_fkx    INDEX     |   CREATE INDEX waterbnd_srf_objclass_fkx ON citydb.waterboundary_surface USING btree (objectclass_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.waterbnd_srf_objclass_fkx;
       citydb            postgres    false    275                       1259    33348    waterbod_to_waterbnd_fkx    INDEX     �   CREATE INDEX waterbod_to_waterbnd_fkx ON citydb.waterbod_to_waterbnd_srf USING btree (waterboundary_surface_id) WITH (fillfactor='90');
 ,   DROP INDEX citydb.waterbod_to_waterbnd_fkx;
       citydb            postgres    false    274                       1259    33349    waterbod_to_waterbnd_fkx1    INDEX     }   CREATE INDEX waterbod_to_waterbnd_fkx1 ON citydb.waterbod_to_waterbnd_srf USING btree (waterbody_id) WITH (fillfactor='90');
 -   DROP INDEX citydb.waterbod_to_waterbnd_fkx1;
       citydb            postgres    false    274            �           1259    35454    waterbody_lod0curve_spx    INDEX     X   CREATE INDEX waterbody_lod0curve_spx ON citydb.waterbody USING gist (lod0_multi_curve);
 +   DROP INDEX citydb.waterbody_lod0curve_spx;
       citydb            postgres    false    273    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33342    waterbody_lod0msrf_fkx    INDEX     t   CREATE INDEX waterbody_lod0msrf_fkx ON citydb.waterbody USING btree (lod0_multi_surface_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.waterbody_lod0msrf_fkx;
       citydb            postgres    false    273            �           1259    35469    waterbody_lod1curve_spx    INDEX     X   CREATE INDEX waterbody_lod1curve_spx ON citydb.waterbody USING gist (lod1_multi_curve);
 +   DROP INDEX citydb.waterbody_lod1curve_spx;
       citydb            postgres    false    273    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2    2            �           1259    33343    waterbody_lod1msrf_fkx    INDEX     t   CREATE INDEX waterbody_lod1msrf_fkx ON citydb.waterbody USING btree (lod1_multi_surface_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.waterbody_lod1msrf_fkx;
       citydb            postgres    false    273            �           1259    33344    waterbody_lod1solid_fkx    INDEX     m   CREATE INDEX waterbody_lod1solid_fkx ON citydb.waterbody USING btree (lod1_solid_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.waterbody_lod1solid_fkx;
       citydb            postgres    false    273            �           1259    33345    waterbody_lod2solid_fkx    INDEX     m   CREATE INDEX waterbody_lod2solid_fkx ON citydb.waterbody USING btree (lod2_solid_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.waterbody_lod2solid_fkx;
       citydb            postgres    false    273            �           1259    33346    waterbody_lod3solid_fkx    INDEX     m   CREATE INDEX waterbody_lod3solid_fkx ON citydb.waterbody USING btree (lod3_solid_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.waterbody_lod3solid_fkx;
       citydb            postgres    false    273            �           1259    33347    waterbody_lod4solid_fkx    INDEX     m   CREATE INDEX waterbody_lod4solid_fkx ON citydb.waterbody USING btree (lod4_solid_id) WITH (fillfactor='90');
 +   DROP INDEX citydb.waterbody_lod4solid_fkx;
       citydb            postgres    false    273            �           1259    33565    waterbody_objclass_fkx    INDEX     m   CREATE INDEX waterbody_objclass_fkx ON citydb.waterbody USING btree (objectclass_id) WITH (fillfactor='90');
 *   DROP INDEX citydb.waterbody_objclass_fkx;
       citydb            postgres    false    273                       2606    34941 &   address_to_bridge address_to_bridge_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 P   ALTER TABLE ONLY citydb.address_to_bridge DROP CONSTRAINT address_to_bridge_fk;
       citydb          postgres    false    293    299    7134                       2606    34946 '   address_to_bridge address_to_bridge_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_bridge
    ADD CONSTRAINT address_to_bridge_fk1 FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.address_to_bridge DROP CONSTRAINT address_to_bridge_fk1;
       citydb          postgres    false    7019    293    285            +           2606    33761 *   address_to_building address_to_building_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 T   ALTER TABLE ONLY citydb.address_to_building DROP CONSTRAINT address_to_building_fk;
       citydb          postgres    false    7134    299    250            ,           2606    33766 +   address_to_building address_to_building_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.address_to_building
    ADD CONSTRAINT address_to_building_fk1 FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.address_to_building DROP CONSTRAINT address_to_building_fk1;
       citydb          postgres    false    250    6759    251            ,           2606    35046 %   aggregation_info aggregation_info_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk1 FOREIGN KEY (child_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 O   ALTER TABLE ONLY citydb.aggregation_info DROP CONSTRAINT aggregation_info_fk1;
       citydb          postgres    false    312    244    6682            -           2606    35051 %   aggregation_info aggregation_info_fk2    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.aggregation_info
    ADD CONSTRAINT aggregation_info_fk2 FOREIGN KEY (parent_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 O   ALTER TABLE ONLY citydb.aggregation_info DROP CONSTRAINT aggregation_info_fk2;
       citydb          postgres    false    312    6682    244            b           2606    34036 *   appear_to_surface_data app_to_surf_data_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 T   ALTER TABLE ONLY citydb.appear_to_surface_data DROP CONSTRAINT app_to_surf_data_fk;
       citydb          postgres    false    261    300    7139            c           2606    34041 +   appear_to_surface_data app_to_surf_data_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.appear_to_surface_data
    ADD CONSTRAINT app_to_surf_data_fk1 FOREIGN KEY (appearance_id) REFERENCES citydb.appearance(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.appear_to_surface_data DROP CONSTRAINT app_to_surf_data_fk1;
       citydb          postgres    false    261    7117    296                       2606    34961 "   appearance appearance_citymodel_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_citymodel_fk FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;
 L   ALTER TABLE ONLY citydb.appearance DROP CONSTRAINT appearance_citymodel_fk;
       citydb          postgres    false    301    296    7145                       2606    34956 #   appearance appearance_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.appearance
    ADD CONSTRAINT appearance_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.appearance DROP CONSTRAINT appearance_cityobject_fk;
       citydb          postgres    false    295    296    7112            ;           2606    33841 *   building_furniture bldg_furn_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT bldg_furn_cityobject_fk;
       citydb          postgres    false    7112    295    252            <           2606    33851 (   building_furniture bldg_furn_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT bldg_furn_lod4brep_fk;
       citydb          postgres    false    298    7131    252            =           2606    33856 (   building_furniture bldg_furn_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT bldg_furn_lod4impl_fk;
       citydb          postgres    false    7123    297    252            >           2606    33861 (   building_furniture bldg_furn_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT bldg_furn_objclass_fk;
       citydb          postgres    false    6682    244    252            ?           2606    33846 $   building_furniture bldg_furn_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_furniture
    ADD CONSTRAINT bldg_furn_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.building_furniture DROP CONSTRAINT bldg_furn_room_fk;
       citydb          postgres    false    256    6805    252            @           2606    33876 +   building_installation bldg_inst_building_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_building_fk;
       citydb          postgres    false    253    6759    251            A           2606    33866 -   building_installation bldg_inst_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_cityobject_fk;
       citydb          postgres    false    7112    253    295            B           2606    33886 +   building_installation bldg_inst_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod2brep_fk;
       citydb          postgres    false    298    253    7131            C           2606    33901 +   building_installation bldg_inst_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod2impl_fk;
       citydb          postgres    false    253    7123    297            D           2606    33891 +   building_installation bldg_inst_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod3brep_fk;
       citydb          postgres    false    7131    253    298            E           2606    33906 +   building_installation bldg_inst_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod3impl_fk;
       citydb          postgres    false    297    7123    253            F           2606    33896 +   building_installation bldg_inst_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod4brep_fk;
       citydb          postgres    false    298    253    7131            G           2606    33911 +   building_installation bldg_inst_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_lod4impl_fk;
       citydb          postgres    false    297    253    7123            H           2606    33871 +   building_installation bldg_inst_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_objclass_fk;
       citydb          postgres    false    253    6682    244            I           2606    33881 '   building_installation bldg_inst_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building_installation
    ADD CONSTRAINT bldg_inst_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.building_installation DROP CONSTRAINT bldg_inst_room_fk;
       citydb          postgres    false    6805    253    256            �           2606    34806 /   bridge_open_to_them_srf brd_open_to_them_srf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk FOREIGN KEY (bridge_opening_id) REFERENCES citydb.bridge_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_open_to_them_srf DROP CONSTRAINT brd_open_to_them_srf_fk;
       citydb          postgres    false    289    7055    288            �           2606    34811 0   bridge_open_to_them_srf brd_open_to_them_srf_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_open_to_them_srf
    ADD CONSTRAINT brd_open_to_them_srf_fk1 FOREIGN KEY (bridge_thematic_surface_id) REFERENCES citydb.bridge_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_open_to_them_srf DROP CONSTRAINT brd_open_to_them_srf_fk1;
       citydb          postgres    false    289    7075    291                       2606    34866 1   bridge_thematic_surface brd_them_srf_brd_const_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_const_fk FOREIGN KEY (bridge_constr_element_id) REFERENCES citydb.bridge_constr_element(id) MATCH FULL ON UPDATE CASCADE;
 [   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_brd_const_fk;
       citydb          postgres    false    7086    292    291                       2606    34861 0   bridge_thematic_surface brd_them_srf_brd_inst_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_inst_fk FOREIGN KEY (bridge_installation_id) REFERENCES citydb.bridge_installation(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_brd_inst_fk;
       citydb          postgres    false    291    7045    287                       2606    34856 0   bridge_thematic_surface brd_them_srf_brd_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_brd_room_fk;
       citydb          postgres    false    291    290    7065                       2606    34851 .   bridge_thematic_surface brd_them_srf_bridge_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_bridge_fk;
       citydb          postgres    false    291    7019    285                       2606    34841 /   bridge_thematic_surface brd_them_srf_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_cityobj_fk;
       citydb          postgres    false    7112    291    295                       2606    34871 0   bridge_thematic_surface brd_them_srf_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_lod2msrf_fk;
       citydb          postgres    false    298    7131    291            	           2606    34876 0   bridge_thematic_surface brd_them_srf_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_lod3msrf_fk;
       citydb          postgres    false    291    298    7131            
           2606    34881 0   bridge_thematic_surface brd_them_srf_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_lod4msrf_fk;
       citydb          postgres    false    298    291    7131                       2606    34846 0   bridge_thematic_surface brd_them_srf_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_thematic_surface
    ADD CONSTRAINT brd_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.bridge_thematic_surface DROP CONSTRAINT brd_them_srf_objclass_fk;
       citydb          postgres    false    244    291    6682            d           2606    34051 *   breakline_relief breakline_rel_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.breakline_relief DROP CONSTRAINT breakline_rel_objclass_fk;
       citydb          postgres    false    244    6682    262            e           2606    34046 )   breakline_relief breakline_relief_comp_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.breakline_relief
    ADD CONSTRAINT breakline_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.breakline_relief DROP CONSTRAINT breakline_relief_comp_fk;
       citydb          postgres    false    6835    264    262            �           2606    34636    bridge bridge_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_cityobject_fk;
       citydb          postgres    false    285    7112    295                       2606    34891 -   bridge_constr_element bridge_constr_bridge_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_bridge_fk;
       citydb          postgres    false    7019    292    285                       2606    34886 .   bridge_constr_element bridge_constr_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_cityobj_fk;
       citydb          postgres    false    295    292    7112                       2606    34896 /   bridge_constr_element bridge_constr_lod1brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod1brep_fk;
       citydb          postgres    false    292    7131    298                       2606    34916 /   bridge_constr_element bridge_constr_lod1impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod1impl_fk;
       citydb          postgres    false    7123    297    292                       2606    34901 /   bridge_constr_element bridge_constr_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod2brep_fk;
       citydb          postgres    false    298    7131    292                       2606    34921 /   bridge_constr_element bridge_constr_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod2impl_fk;
       citydb          postgres    false    292    7123    297                       2606    34906 /   bridge_constr_element bridge_constr_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod3brep_fk;
       citydb          postgres    false    7131    298    292                       2606    34926 /   bridge_constr_element bridge_constr_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod3impl_fk;
       citydb          postgres    false    297    292    7123                       2606    34911 /   bridge_constr_element bridge_constr_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod4brep_fk;
       citydb          postgres    false    7131    298    292                       2606    34931 /   bridge_constr_element bridge_constr_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_lod4impl_fk;
       citydb          postgres    false    292    7123    297                       2606    34936 /   bridge_constr_element bridge_constr_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_constr_element
    ADD CONSTRAINT bridge_constr_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.bridge_constr_element DROP CONSTRAINT bridge_constr_objclass_fk;
       citydb          postgres    false    244    292    6682            �           2606    34701 (   bridge_furniture bridge_furn_brd_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furn_brd_room_fk;
       citydb          postgres    false    290    7065    286            �           2606    34696 *   bridge_furniture bridge_furn_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furn_cityobject_fk;
       citydb          postgres    false    286    7112    295            �           2606    34706 (   bridge_furniture bridge_furn_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furn_lod4brep_fk;
       citydb          postgres    false    7131    298    286            �           2606    34711 (   bridge_furniture bridge_furn_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furn_lod4impl_fk;
       citydb          postgres    false    297    286    7123            �           2606    34716 (   bridge_furniture bridge_furn_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_furniture
    ADD CONSTRAINT bridge_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.bridge_furniture DROP CONSTRAINT bridge_furn_objclass_fk;
       citydb          postgres    false    244    286    6682            �           2606    34736 +   bridge_installation bridge_inst_brd_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_brd_room_fk FOREIGN KEY (bridge_room_id) REFERENCES citydb.bridge_room(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_brd_room_fk;
       citydb          postgres    false    7065    287    290            �           2606    34731 )   bridge_installation bridge_inst_bridge_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_bridge_fk;
       citydb          postgres    false    287    7019    285            �           2606    34721 -   bridge_installation bridge_inst_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_cityobject_fk;
       citydb          postgres    false    295    287    7112            �           2606    34741 +   bridge_installation bridge_inst_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod2brep_fk;
       citydb          postgres    false    298    7131    287            �           2606    34756 +   bridge_installation bridge_inst_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod2impl_fk;
       citydb          postgres    false    287    297    7123            �           2606    34746 +   bridge_installation bridge_inst_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod3brep_fk;
       citydb          postgres    false    287    7131    298            �           2606    34761 +   bridge_installation bridge_inst_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod3impl_fk;
       citydb          postgres    false    287    7123    297            �           2606    34751 +   bridge_installation bridge_inst_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod4brep_fk;
       citydb          postgres    false    287    298    7131            �           2606    34766 +   bridge_installation bridge_inst_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_lod4impl_fk;
       citydb          postgres    false    287    7123    297            �           2606    34726 +   bridge_installation bridge_inst_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_installation
    ADD CONSTRAINT bridge_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.bridge_installation DROP CONSTRAINT bridge_inst_objclass_fk;
       citydb          postgres    false    244    287    6682            �           2606    34651    bridge bridge_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod1msrf_fk;
       citydb          postgres    false    285    7131    298            �           2606    34671    bridge bridge_lod1solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod1solid_fk;
       citydb          postgres    false    285    298    7131            �           2606    34656    bridge bridge_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod2msrf_fk;
       citydb          postgres    false    285    7131    298            �           2606    34676    bridge bridge_lod2solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod2solid_fk;
       citydb          postgres    false    285    298    7131            �           2606    34661    bridge bridge_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod3msrf_fk;
       citydb          postgres    false    285    7131    298            �           2606    34681    bridge bridge_lod3solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod3solid_fk;
       citydb          postgres    false    285    298    7131            �           2606    34666    bridge bridge_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod4msrf_fk;
       citydb          postgres    false    285    7131    298            �           2606    34686    bridge bridge_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_lod4solid_fk;
       citydb          postgres    false    285    298    7131            �           2606    34691    bridge bridge_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 F   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_objectclass_fk;
       citydb          postgres    false    6682    244    285            �           2606    34781 %   bridge_opening bridge_open_address_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_address_fk;
       citydb          postgres    false    288    7134    299            �           2606    34771 (   bridge_opening bridge_open_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_cityobject_fk;
       citydb          postgres    false    288    7112    295            �           2606    34796 &   bridge_opening bridge_open_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_lod3impl_fk;
       citydb          postgres    false    288    7123    297            �           2606    34786 &   bridge_opening bridge_open_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_lod3msrf_fk;
       citydb          postgres    false    288    7131    298            �           2606    34801 &   bridge_opening bridge_open_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_lod4impl_fk;
       citydb          postgres    false    288    7123    297            �           2606    34791 &   bridge_opening bridge_open_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_lod4msrf_fk;
       citydb          postgres    false    288    7131    298            �           2606    34776 &   bridge_opening bridge_open_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_opening
    ADD CONSTRAINT bridge_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.bridge_opening DROP CONSTRAINT bridge_open_objclass_fk;
       citydb          postgres    false    288    6682    244            �           2606    34641    bridge bridge_parent_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_parent_fk FOREIGN KEY (bridge_parent_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 A   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_parent_fk;
       citydb          postgres    false    285    7019    285            �           2606    34821 !   bridge_room bridge_room_bridge_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_bridge_fk FOREIGN KEY (bridge_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 K   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_bridge_fk;
       citydb          postgres    false    290    285    7019            �           2606    34816 %   bridge_room bridge_room_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_cityobject_fk;
       citydb          postgres    false    290    295    7112                        2606    34826 #   bridge_room bridge_room_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_lod4msrf_fk;
       citydb          postgres    false    298    290    7131                       2606    34831 $   bridge_room bridge_room_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_lod4solid_fk;
       citydb          postgres    false    290    298    7131                       2606    34836 #   bridge_room bridge_room_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge_room
    ADD CONSTRAINT bridge_room_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.bridge_room DROP CONSTRAINT bridge_room_objclass_fk;
       citydb          postgres    false    290    244    6682            �           2606    34646    bridge bridge_root_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.bridge
    ADD CONSTRAINT bridge_root_fk FOREIGN KEY (bridge_root_id) REFERENCES citydb.bridge(id) MATCH FULL ON UPDATE CASCADE;
 ?   ALTER TABLE ONLY citydb.bridge DROP CONSTRAINT bridge_root_fk;
       citydb          postgres    false    285    7019    285            -           2606    33771    building building_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 I   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_cityobject_fk;
       citydb          postgres    false    295    251    7112            .           2606    33786 "   building building_lod0footprint_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0footprint_fk FOREIGN KEY (lod0_footprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 L   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod0footprint_fk;
       citydb          postgres    false    7131    251    298            /           2606    33791 "   building building_lod0roofprint_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod0roofprint_fk FOREIGN KEY (lod0_roofprint_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 L   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod0roofprint_fk;
       citydb          postgres    false    251    298    7131            0           2606    33796    building building_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod1msrf_fk;
       citydb          postgres    false    251    298    7131            1           2606    33816    building building_lod1solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 H   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod1solid_fk;
       citydb          postgres    false    251    298    7131            2           2606    33801    building building_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod2msrf_fk;
       citydb          postgres    false    7131    251    298            3           2606    33821    building building_lod2solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 H   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod2solid_fk;
       citydb          postgres    false    298    251    7131            4           2606    33806    building building_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod3msrf_fk;
       citydb          postgres    false    298    7131    251            5           2606    33826    building building_lod3solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 H   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod3solid_fk;
       citydb          postgres    false    298    7131    251            6           2606    33811    building building_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod4msrf_fk;
       citydb          postgres    false    251    298    7131            7           2606    33831    building building_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 H   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_lod4solid_fk;
       citydb          postgres    false    298    251    7131            8           2606    33836     building building_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 J   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_objectclass_fk;
       citydb          postgres    false    244    251    6682            9           2606    33776    building building_parent_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_parent_fk FOREIGN KEY (building_parent_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_parent_fk;
       citydb          postgres    false    6759    251    251            :           2606    33781    building building_root_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.building
    ADD CONSTRAINT building_root_fk FOREIGN KEY (building_root_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.building DROP CONSTRAINT building_root_fk;
       citydb          postgres    false    251    6759    251                       2606    33651 &   city_furniture city_furn_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_cityobject_fk;
       citydb          postgres    false    246    7112    295                       2606    33656 $   city_furniture city_furn_lod1brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod1brep_fk;
       citydb          postgres    false    246    7131    298                       2606    33676 $   city_furniture city_furn_lod1impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod1impl_fk;
       citydb          postgres    false    7123    246    297                       2606    33661 $   city_furniture city_furn_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod2brep_fk;
       citydb          postgres    false    298    246    7131                       2606    33681 $   city_furniture city_furn_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod2impl_fk;
       citydb          postgres    false    297    7123    246                       2606    33666 $   city_furniture city_furn_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod3brep_fk;
       citydb          postgres    false    7131    246    298                       2606    33686 $   city_furniture city_furn_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod3impl_fk;
       citydb          postgres    false    246    7123    297                       2606    33671 $   city_furniture city_furn_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod4brep_fk;
       citydb          postgres    false    7131    246    298                       2606    33691 $   city_furniture city_furn_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_lod4impl_fk;
       citydb          postgres    false    297    246    7123                       2606    33696 $   city_furniture city_furn_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.city_furniture
    ADD CONSTRAINT city_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.city_furniture DROP CONSTRAINT city_furn_objclass_fk;
       citydb          postgres    false    244    246    6682                       2606    33586 &   cityobject_member cityobject_member_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 P   ALTER TABLE ONLY citydb.cityobject_member DROP CONSTRAINT cityobject_member_fk;
       citydb          postgres    false    7112    295    237            	           2606    33591 '   cityobject_member cityobject_member_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_member
    ADD CONSTRAINT cityobject_member_fk1 FOREIGN KEY (citymodel_id) REFERENCES citydb.citymodel(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.cityobject_member DROP CONSTRAINT cityobject_member_fk1;
       citydb          postgres    false    237    7145    301                       2606    34951 $   cityobject cityobject_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject
    ADD CONSTRAINT cityobject_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.cityobject DROP CONSTRAINT cityobject_objectclass_fk;
       citydb          postgres    false    295    244    6682            &           2606    35016 (   external_reference ext_ref_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.external_reference
    ADD CONSTRAINT ext_ref_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.external_reference DROP CONSTRAINT ext_ref_cityobject_fk;
       citydb          postgres    false    295    7112    303                       2606    33701 +   generic_cityobject gen_object_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_cityobject_fk;
       citydb          postgres    false    248    295    7112                        2606    33706 )   generic_cityobject gen_object_lod0brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0brep_fk FOREIGN KEY (lod0_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod0brep_fk;
       citydb          postgres    false    7131    248    298            !           2606    33731 )   generic_cityobject gen_object_lod0impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod0impl_fk FOREIGN KEY (lod0_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod0impl_fk;
       citydb          postgres    false    7123    248    297            "           2606    33711 )   generic_cityobject gen_object_lod1brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod1brep_fk;
       citydb          postgres    false    248    7131    298            #           2606    33736 )   generic_cityobject gen_object_lod1impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod1impl_fk;
       citydb          postgres    false    7123    297    248            $           2606    33716 )   generic_cityobject gen_object_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod2brep_fk;
       citydb          postgres    false    248    7131    298            %           2606    33741 )   generic_cityobject gen_object_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod2impl_fk;
       citydb          postgres    false    297    248    7123            &           2606    33721 )   generic_cityobject gen_object_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod3brep_fk;
       citydb          postgres    false    7131    298    248            '           2606    33746 )   generic_cityobject gen_object_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod3impl_fk;
       citydb          postgres    false    248    297    7123            (           2606    33726 )   generic_cityobject gen_object_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod4brep_fk;
       citydb          postgres    false    298    248    7131            )           2606    33751 )   generic_cityobject gen_object_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_lod4impl_fk;
       citydb          postgres    false    248    7123    297            *           2606    33756 )   generic_cityobject gen_object_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generic_cityobject
    ADD CONSTRAINT gen_object_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.generic_cityobject DROP CONSTRAINT gen_object_objclass_fk;
       citydb          postgres    false    248    244    6682            
           2606    33596 $   generalization general_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 N   ALTER TABLE ONLY citydb.generalization DROP CONSTRAINT general_cityobject_fk;
       citydb          postgres    false    239    295    7112                       2606    33601 (   generalization general_generalizes_to_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.generalization
    ADD CONSTRAINT general_generalizes_to_fk FOREIGN KEY (generalizes_to_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 R   ALTER TABLE ONLY citydb.generalization DROP CONSTRAINT general_generalizes_to_fk;
       citydb          postgres    false    295    7112    239            "           2606    35011 1   cityobject_genericattrib genericattrib_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 [   ALTER TABLE ONLY citydb.cityobject_genericattrib DROP CONSTRAINT genericattrib_cityobj_fk;
       citydb          postgres    false    302    7112    295            #           2606    35006 .   cityobject_genericattrib genericattrib_geom_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.cityobject_genericattrib DROP CONSTRAINT genericattrib_geom_fk;
       citydb          postgres    false    298    7131    302            $           2606    34996 0   cityobject_genericattrib genericattrib_parent_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_parent_fk FOREIGN KEY (parent_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.cityobject_genericattrib DROP CONSTRAINT genericattrib_parent_fk;
       citydb          postgres    false    302    7147    302            %           2606    35001 .   cityobject_genericattrib genericattrib_root_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobject_genericattrib
    ADD CONSTRAINT genericattrib_root_fk FOREIGN KEY (root_genattrib_id) REFERENCES citydb.cityobject_genericattrib(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.cityobject_genericattrib DROP CONSTRAINT genericattrib_root_fk;
       citydb          postgres    false    302    7147    302                       2606    33611    cityobjectgroup group_brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_brep_fk FOREIGN KEY (brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.cityobjectgroup DROP CONSTRAINT group_brep_fk;
       citydb          postgres    false    7131    241    298                       2606    33606 #   cityobjectgroup group_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.cityobjectgroup DROP CONSTRAINT group_cityobject_fk;
       citydb          postgres    false    295    241    7112                       2606    33621 $   cityobjectgroup group_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 N   ALTER TABLE ONLY citydb.cityobjectgroup DROP CONSTRAINT group_objectclass_fk;
       citydb          postgres    false    6682    241    244                       2606    33616 '   cityobjectgroup group_parent_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.cityobjectgroup
    ADD CONSTRAINT group_parent_cityobj_fk FOREIGN KEY (parent_cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.cityobjectgroup DROP CONSTRAINT group_parent_cityobj_fk;
       citydb          postgres    false    7112    241    295                       2606    33626 *   group_to_cityobject group_to_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 T   ALTER TABLE ONLY citydb.group_to_cityobject DROP CONSTRAINT group_to_cityobject_fk;
       citydb          postgres    false    242    295    7112                       2606    33631 +   group_to_cityobject group_to_cityobject_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.group_to_cityobject
    ADD CONSTRAINT group_to_cityobject_fk1 FOREIGN KEY (cityobjectgroup_id) REFERENCES citydb.cityobjectgroup(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.group_to_cityobject DROP CONSTRAINT group_to_cityobject_fk1;
       citydb          postgres    false    241    6669    242                       2606    34966 '   implicit_geometry implicit_geom_brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.implicit_geometry
    ADD CONSTRAINT implicit_geom_brep_fk FOREIGN KEY (relative_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.implicit_geometry DROP CONSTRAINT implicit_geom_brep_fk;
       citydb          postgres    false    298    297    7131            }           2606    34171    land_use land_use_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 I   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_cityobject_fk;
       citydb          postgres    false    295    7112    270            ~           2606    34176    land_use land_use_lod0msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_lod0msrf_fk;
       citydb          postgres    false    270    7131    298                       2606    34181    land_use land_use_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_lod1msrf_fk;
       citydb          postgres    false    7131    298    270            �           2606    34186    land_use land_use_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_lod2msrf_fk;
       citydb          postgres    false    270    298    7131            �           2606    34191    land_use land_use_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_lod3msrf_fk;
       citydb          postgres    false    298    270    7131            �           2606    34196    land_use land_use_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_lod4msrf_fk;
       citydb          postgres    false    270    298    7131            �           2606    34201    land_use land_use_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.land_use
    ADD CONSTRAINT land_use_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.land_use DROP CONSTRAINT land_use_objclass_fk;
       citydb          postgres    false    270    244    6682            f           2606    34061 *   masspoint_relief masspoint_rel_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_rel_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.masspoint_relief DROP CONSTRAINT masspoint_rel_objclass_fk;
       citydb          postgres    false    263    6682    244            g           2606    34056 )   masspoint_relief masspoint_relief_comp_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.masspoint_relief
    ADD CONSTRAINT masspoint_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.masspoint_relief DROP CONSTRAINT masspoint_relief_comp_fk;
       citydb          postgres    false    6835    263    264                       2606    33646    objectclass objectclass_ade_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 H   ALTER TABLE ONLY citydb.objectclass DROP CONSTRAINT objectclass_ade_fk;
       citydb          postgres    false    244    7171    311                       2606    33641 $   objectclass objectclass_baseclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_baseclass_fk FOREIGN KEY (baseclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 N   ALTER TABLE ONLY citydb.objectclass DROP CONSTRAINT objectclass_baseclass_fk;
       citydb          postgres    false    244    244    6682                       2606    33636 %   objectclass objectclass_superclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.objectclass
    ADD CONSTRAINT objectclass_superclass_fk FOREIGN KEY (superclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 O   ALTER TABLE ONLY citydb.objectclass DROP CONSTRAINT objectclass_superclass_fk;
       citydb          postgres    false    244    244    6682            Q           2606    33951 /   opening_to_them_surface open_to_them_surface_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk FOREIGN KEY (opening_id) REFERENCES citydb.opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.opening_to_them_surface DROP CONSTRAINT open_to_them_surface_fk;
       citydb          postgres    false    254    255    6795            R           2606    33956 0   opening_to_them_surface open_to_them_surface_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening_to_them_surface
    ADD CONSTRAINT open_to_them_surface_fk1 FOREIGN KEY (thematic_surface_id) REFERENCES citydb.thematic_surface(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.opening_to_them_surface DROP CONSTRAINT open_to_them_surface_fk1;
       citydb          postgres    false    255    257    6814            J           2606    33926    opening opening_address_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_address_fk FOREIGN KEY (address_id) REFERENCES citydb.address(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_address_fk;
       citydb          postgres    false    299    254    7134            K           2606    33916    opening opening_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_cityobject_fk;
       citydb          postgres    false    7112    295    254            L           2606    33941    opening opening_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_lod3impl_fk;
       citydb          postgres    false    254    297    7123            M           2606    33931    opening opening_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_lod3msrf_fk;
       citydb          postgres    false    298    254    7131            N           2606    33946    opening opening_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_lod4impl_fk;
       citydb          postgres    false    254    297    7123            O           2606    33936    opening opening_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_lod4msrf_fk;
       citydb          postgres    false    254    298    7131            P           2606    33921    opening opening_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.opening
    ADD CONSTRAINT opening_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 H   ALTER TABLE ONLY citydb.opening DROP CONSTRAINT opening_objectclass_fk;
       citydb          postgres    false    6682    244    254            �           2606    34206 %   plant_cover plant_cover_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_cityobject_fk;
       citydb          postgres    false    7112    295    271            �           2606    34231 %   plant_cover plant_cover_lod1msolid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msolid_fk FOREIGN KEY (lod1_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod1msolid_fk;
       citydb          postgres    false    271    7131    298            �           2606    34211 #   plant_cover plant_cover_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod1msrf_fk;
       citydb          postgres    false    271    7131    298            �           2606    34236 %   plant_cover plant_cover_lod2msolid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msolid_fk FOREIGN KEY (lod2_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod2msolid_fk;
       citydb          postgres    false    271    7131    298            �           2606    34216 #   plant_cover plant_cover_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod2msrf_fk;
       citydb          postgres    false    271    7131    298            �           2606    34241 %   plant_cover plant_cover_lod3msolid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msolid_fk FOREIGN KEY (lod3_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod3msolid_fk;
       citydb          postgres    false    271    7131    298            �           2606    34221 #   plant_cover plant_cover_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod3msrf_fk;
       citydb          postgres    false    271    7131    298            �           2606    34246 %   plant_cover plant_cover_lod4msolid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msolid_fk FOREIGN KEY (lod4_multi_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod4msolid_fk;
       citydb          postgres    false    271    7131    298            �           2606    34226 #   plant_cover plant_cover_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_lod4msrf_fk;
       citydb          postgres    false    271    7131    298            �           2606    34251 #   plant_cover plant_cover_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.plant_cover
    ADD CONSTRAINT plant_cover_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.plant_cover DROP CONSTRAINT plant_cover_objclass_fk;
       citydb          postgres    false    271    6682    244            �           2606    34381 #   raster_relief raster_relief_comp_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;
 M   ALTER TABLE ONLY citydb.raster_relief DROP CONSTRAINT raster_relief_comp_fk;
       citydb          postgres    false    276    6835    264            �           2606    34386 '   raster_relief raster_relief_coverage_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_coverage_fk FOREIGN KEY (coverage_id) REFERENCES citydb.grid_coverage(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.raster_relief DROP CONSTRAINT raster_relief_coverage_fk;
       citydb          postgres    false    276    7158    305            �           2606    34391 '   raster_relief raster_relief_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.raster_relief
    ADD CONSTRAINT raster_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.raster_relief DROP CONSTRAINT raster_relief_objclass_fk;
       citydb          postgres    false    276    6682    244            j           2606    34076 /   relief_feat_to_rel_comp rel_feat_to_rel_comp_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk FOREIGN KEY (relief_component_id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp DROP CONSTRAINT rel_feat_to_rel_comp_fk;
       citydb          postgres    false    264    6835    265            k           2606    34081 0   relief_feat_to_rel_comp rel_feat_to_rel_comp_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp
    ADD CONSTRAINT rel_feat_to_rel_comp_fk1 FOREIGN KEY (relief_feature_id) REFERENCES citydb.relief_feature(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.relief_feat_to_rel_comp DROP CONSTRAINT rel_feat_to_rel_comp_fk1;
       citydb          postgres    false    265    266    6842            h           2606    34066 *   relief_component relief_comp_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.relief_component DROP CONSTRAINT relief_comp_cityobject_fk;
       citydb          postgres    false    264    7112    295            i           2606    34071 (   relief_component relief_comp_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_component
    ADD CONSTRAINT relief_comp_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.relief_component DROP CONSTRAINT relief_comp_objclass_fk;
       citydb          postgres    false    264    244    6682            l           2606    34086 (   relief_feature relief_feat_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.relief_feature DROP CONSTRAINT relief_feat_cityobject_fk;
       citydb          postgres    false    295    266    7112            m           2606    34091 &   relief_feature relief_feat_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.relief_feature
    ADD CONSTRAINT relief_feat_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.relief_feature DROP CONSTRAINT relief_feat_objclass_fk;
       citydb          postgres    false    6682    244    266            S           2606    33966    room room_building_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 ?   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_building_fk;
       citydb          postgres    false    256    6759    251            T           2606    33961    room room_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 A   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_cityobject_fk;
       citydb          postgres    false    295    7112    256            U           2606    33971    room room_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 ?   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_lod4msrf_fk;
       citydb          postgres    false    7131    298    256            V           2606    33976    room room_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 @   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_lod4solid_fk;
       citydb          postgres    false    7131    298    256            W           2606    33981    room room_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.room
    ADD CONSTRAINT room_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 B   ALTER TABLE ONLY citydb.room DROP CONSTRAINT room_objectclass_fk;
       citydb          postgres    false    244    256    6682            '           2606    35021    schema schema_ade_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.schema
    ADD CONSTRAINT schema_ade_fk FOREIGN KEY (ade_id) REFERENCES citydb.ade(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 >   ALTER TABLE ONLY citydb.schema DROP CONSTRAINT schema_ade_fk;
       citydb          postgres    false    311    308    7171            *           2606    35036 )   schema_referencing schema_referencing_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk1 FOREIGN KEY (referencing_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 S   ALTER TABLE ONLY citydb.schema_referencing DROP CONSTRAINT schema_referencing_fk1;
       citydb          postgres    false    310    308    7161            +           2606    35041 )   schema_referencing schema_referencing_fk2    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_referencing
    ADD CONSTRAINT schema_referencing_fk2 FOREIGN KEY (referenced_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 S   ALTER TABLE ONLY citydb.schema_referencing DROP CONSTRAINT schema_referencing_fk2;
       citydb          postgres    false    308    310    7161            (           2606    35026 /   schema_to_objectclass schema_to_objectclass_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk1 FOREIGN KEY (schema_id) REFERENCES citydb.schema(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.schema_to_objectclass DROP CONSTRAINT schema_to_objectclass_fk1;
       citydb          postgres    false    7161    309    308            )           2606    35031 /   schema_to_objectclass schema_to_objectclass_fk2    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.schema_to_objectclass
    ADD CONSTRAINT schema_to_objectclass_fk2 FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.schema_to_objectclass DROP CONSTRAINT schema_to_objectclass_fk2;
       citydb          postgres    false    6682    309    244            �           2606    34256 1   solitary_vegetat_object sol_veg_obj_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 [   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_cityobject_fk;
       citydb          postgres    false    272    7112    295            �           2606    34261 /   solitary_vegetat_object sol_veg_obj_lod1brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1brep_fk FOREIGN KEY (lod1_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod1brep_fk;
       citydb          postgres    false    272    7131    298            �           2606    34281 /   solitary_vegetat_object sol_veg_obj_lod1impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod1impl_fk FOREIGN KEY (lod1_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod1impl_fk;
       citydb          postgres    false    272    7123    297            �           2606    34266 /   solitary_vegetat_object sol_veg_obj_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod2brep_fk;
       citydb          postgres    false    272    7131    298            �           2606    34286 /   solitary_vegetat_object sol_veg_obj_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod2impl_fk;
       citydb          postgres    false    272    7123    297            �           2606    34271 /   solitary_vegetat_object sol_veg_obj_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod3brep_fk;
       citydb          postgres    false    272    7131    298            �           2606    34291 /   solitary_vegetat_object sol_veg_obj_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod3impl_fk;
       citydb          postgres    false    272    7123    297            �           2606    34276 /   solitary_vegetat_object sol_veg_obj_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod4brep_fk;
       citydb          postgres    false    272    7131    298            �           2606    34296 /   solitary_vegetat_object sol_veg_obj_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_lod4impl_fk;
       citydb          postgres    false    272    7123    297            �           2606    34301 /   solitary_vegetat_object sol_veg_obj_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.solitary_vegetat_object
    ADD CONSTRAINT sol_veg_obj_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.solitary_vegetat_object DROP CONSTRAINT sol_veg_obj_objclass_fk;
       citydb          postgres    false    272    6682    244                        2606    34991 %   surface_data surface_data_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.surface_data DROP CONSTRAINT surface_data_objclass_fk;
       citydb          postgres    false    300    6682    244            !           2606    34986 &   surface_data surface_data_tex_image_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.surface_data
    ADD CONSTRAINT surface_data_tex_image_fk FOREIGN KEY (tex_image_id) REFERENCES citydb.tex_image(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.surface_data DROP CONSTRAINT surface_data_tex_image_fk;
       citydb          postgres    false    300    304    7156                       2606    34981 (   surface_geometry surface_geom_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_cityobj_fk FOREIGN KEY (cityobject_id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.surface_geometry DROP CONSTRAINT surface_geom_cityobj_fk;
       citydb          postgres    false    7112    295    298                       2606    34971 '   surface_geometry surface_geom_parent_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_parent_fk FOREIGN KEY (parent_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.surface_geometry DROP CONSTRAINT surface_geom_parent_fk;
       citydb          postgres    false    298    298    7131                       2606    34976 %   surface_geometry surface_geom_root_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.surface_geometry
    ADD CONSTRAINT surface_geom_root_fk FOREIGN KEY (root_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.surface_geometry DROP CONSTRAINT surface_geom_root_fk;
       citydb          postgres    false    298    298    7131            `           2606    34026    textureparam texparam_geom_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 G   ALTER TABLE ONLY citydb.textureparam DROP CONSTRAINT texparam_geom_fk;
       citydb          postgres    false    298    260    7131            a           2606    34031 %   textureparam texparam_surface_data_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.textureparam
    ADD CONSTRAINT texparam_surface_data_fk FOREIGN KEY (surface_data_id) REFERENCES citydb.surface_data(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 O   ALTER TABLE ONLY citydb.textureparam DROP CONSTRAINT texparam_surface_data_fk;
       citydb          postgres    false    7139    260    300            X           2606    34006 *   thematic_surface them_surface_bldg_inst_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_bldg_inst_fk FOREIGN KEY (building_installation_id) REFERENCES citydb.building_installation(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_bldg_inst_fk;
       citydb          postgres    false    253    257    6785            Y           2606    33996 )   thematic_surface them_surface_building_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_building_fk FOREIGN KEY (building_id) REFERENCES citydb.building(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_building_fk;
       citydb          postgres    false    251    6759    257            Z           2606    33986 +   thematic_surface them_surface_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_cityobject_fk;
       citydb          postgres    false    295    7112    257            [           2606    34011 )   thematic_surface them_surface_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_lod2msrf_fk;
       citydb          postgres    false    7131    298    257            \           2606    34016 )   thematic_surface them_surface_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_lod3msrf_fk;
       citydb          postgres    false    257    298    7131            ]           2606    34021 )   thematic_surface them_surface_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_lod4msrf_fk;
       citydb          postgres    false    7131    257    298            ^           2606    33991 )   thematic_surface them_surface_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_objclass_fk;
       citydb          postgres    false    257    244    6682            _           2606    34001 %   thematic_surface them_surface_room_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.thematic_surface
    ADD CONSTRAINT them_surface_room_fk FOREIGN KEY (room_id) REFERENCES citydb.room(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.thematic_surface DROP CONSTRAINT them_surface_room_fk;
       citydb          postgres    false    6805    257    256            n           2606    34096    tin_relief tin_relief_comp_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_comp_fk FOREIGN KEY (id) REFERENCES citydb.relief_component(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.tin_relief DROP CONSTRAINT tin_relief_comp_fk;
       citydb          postgres    false    267    6835    264            o           2606    34101    tin_relief tin_relief_geom_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_geom_fk FOREIGN KEY (surface_geometry_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 G   ALTER TABLE ONLY citydb.tin_relief DROP CONSTRAINT tin_relief_geom_fk;
       citydb          postgres    false    7131    298    267            p           2606    34106 !   tin_relief tin_relief_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tin_relief
    ADD CONSTRAINT tin_relief_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 K   ALTER TABLE ONLY citydb.tin_relief DROP CONSTRAINT tin_relief_objclass_fk;
       citydb          postgres    false    267    6682    244            w           2606    34141 '   traffic_area traffic_area_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 Q   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_cityobject_fk;
       citydb          postgres    false    295    7112    269            x           2606    34151 %   traffic_area traffic_area_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_lod2msrf_fk;
       citydb          postgres    false    298    7131    269            y           2606    34156 %   traffic_area traffic_area_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_lod3msrf_fk;
       citydb          postgres    false    269    298    7131            z           2606    34161 %   traffic_area traffic_area_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_lod4msrf_fk;
       citydb          postgres    false    269    298    7131            {           2606    34146 %   traffic_area traffic_area_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 O   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_objclass_fk;
       citydb          postgres    false    6682    269    244            |           2606    34166 &   traffic_area traffic_area_trancmplx_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.traffic_area
    ADD CONSTRAINT traffic_area_trancmplx_fk FOREIGN KEY (transportation_complex_id) REFERENCES citydb.transportation_complex(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.traffic_area DROP CONSTRAINT traffic_area_trancmplx_fk;
       citydb          postgres    false    6857    269    268            q           2606    34116 1   transportation_complex tran_complex_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 [   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_cityobject_fk;
       citydb          postgres    false    7112    268    295            r           2606    34121 /   transportation_complex tran_complex_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_lod1msrf_fk;
       citydb          postgres    false    7131    298    268            s           2606    34126 /   transportation_complex tran_complex_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_lod2msrf_fk;
       citydb          postgres    false    268    7131    298            t           2606    34131 /   transportation_complex tran_complex_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_lod3msrf_fk;
       citydb          postgres    false    268    7131    298            u           2606    34136 /   transportation_complex tran_complex_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_lod4msrf_fk;
       citydb          postgres    false    298    7131    268            v           2606    34111 /   transportation_complex tran_complex_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.transportation_complex
    ADD CONSTRAINT tran_complex_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.transportation_complex DROP CONSTRAINT tran_complex_objclass_fk;
       citydb          postgres    false    6682    268    244            �           2606    34466 )   tunnel_hollow_space tun_hspace_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tun_hspace_cityobj_fk;
       citydb          postgres    false    279    7112    295            �           2606    34476 *   tunnel_hollow_space tun_hspace_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tun_hspace_lod4msrf_fk;
       citydb          postgres    false    279    7131    298            �           2606    34481 +   tunnel_hollow_space tun_hspace_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tun_hspace_lod4solid_fk;
       citydb          postgres    false    279    7131    298            �           2606    34486 *   tunnel_hollow_space tun_hspace_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tun_hspace_objclass_fk;
       citydb          postgres    false    279    6682    244            �           2606    34471 (   tunnel_hollow_space tun_hspace_tunnel_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_hollow_space
    ADD CONSTRAINT tun_hspace_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.tunnel_hollow_space DROP CONSTRAINT tun_hspace_tunnel_fk;
       citydb          postgres    false    279    6946    277            �           2606    34456 /   tunnel_open_to_them_srf tun_open_to_them_srf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk FOREIGN KEY (tunnel_opening_id) REFERENCES citydb.tunnel_opening(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Y   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf DROP CONSTRAINT tun_open_to_them_srf_fk;
       citydb          postgres    false    278    6975    282            �           2606    34461 0   tunnel_open_to_them_srf tun_open_to_them_srf_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf
    ADD CONSTRAINT tun_open_to_them_srf_fk1 FOREIGN KEY (tunnel_thematic_surface_id) REFERENCES citydb.tunnel_thematic_surface(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_open_to_them_srf DROP CONSTRAINT tun_open_to_them_srf_fk1;
       citydb          postgres    false    278    6966    280            �           2606    34491 /   tunnel_thematic_surface tun_them_srf_cityobj_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_cityobj_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 Y   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_cityobj_fk;
       citydb          postgres    false    280    7112    295            �           2606    34506 .   tunnel_thematic_surface tun_them_srf_hspace_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_hspace_fk;
       citydb          postgres    false    280    6957    279            �           2606    34516 0   tunnel_thematic_surface tun_them_srf_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_lod2msrf_fk;
       citydb          postgres    false    280    7131    298            �           2606    34521 0   tunnel_thematic_surface tun_them_srf_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_lod3msrf_fk;
       citydb          postgres    false    280    7131    298            �           2606    34526 0   tunnel_thematic_surface tun_them_srf_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_lod4msrf_fk;
       citydb          postgres    false    280    7131    298            �           2606    34496 0   tunnel_thematic_surface tun_them_srf_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_objclass_fk;
       citydb          postgres    false    280    6682    244            �           2606    34511 0   tunnel_thematic_surface tun_them_srf_tun_inst_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tun_inst_fk FOREIGN KEY (tunnel_installation_id) REFERENCES citydb.tunnel_installation(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_tun_inst_fk;
       citydb          postgres    false    280    6992    283            �           2606    34501 .   tunnel_thematic_surface tun_them_srf_tunnel_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_thematic_surface
    ADD CONSTRAINT tun_them_srf_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.tunnel_thematic_surface DROP CONSTRAINT tun_them_srf_tunnel_fk;
       citydb          postgres    false    280    6946    277            �           2606    34396    tunnel tunnel_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 E   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_cityobject_fk;
       citydb          postgres    false    277    7112    295            �           2606    34611 *   tunnel_furniture tunnel_furn_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 T   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furn_cityobject_fk;
       citydb          postgres    false    284    7112    295            �           2606    34616 &   tunnel_furniture tunnel_furn_hspace_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furn_hspace_fk;
       citydb          postgres    false    284    6957    279            �           2606    34621 (   tunnel_furniture tunnel_furn_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furn_lod4brep_fk;
       citydb          postgres    false    284    7131    298            �           2606    34626 (   tunnel_furniture tunnel_furn_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furn_lod4impl_fk;
       citydb          postgres    false    284    7123    297            �           2606    34631 (   tunnel_furniture tunnel_furn_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_furniture
    ADD CONSTRAINT tunnel_furn_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.tunnel_furniture DROP CONSTRAINT tunnel_furn_objclass_fk;
       citydb          postgres    false    284    6682    244            �           2606    34561 -   tunnel_installation tunnel_inst_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_cityobject_fk;
       citydb          postgres    false    283    7112    295            �           2606    34576 )   tunnel_installation tunnel_inst_hspace_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_hspace_fk FOREIGN KEY (tunnel_hollow_space_id) REFERENCES citydb.tunnel_hollow_space(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_hspace_fk;
       citydb          postgres    false    283    6957    279            �           2606    34581 +   tunnel_installation tunnel_inst_lod2brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2brep_fk FOREIGN KEY (lod2_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod2brep_fk;
       citydb          postgres    false    283    7131    298            �           2606    34596 +   tunnel_installation tunnel_inst_lod2impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod2impl_fk FOREIGN KEY (lod2_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod2impl_fk;
       citydb          postgres    false    283    7123    297            �           2606    34586 +   tunnel_installation tunnel_inst_lod3brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3brep_fk FOREIGN KEY (lod3_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod3brep_fk;
       citydb          postgres    false    283    7131    298            �           2606    34601 +   tunnel_installation tunnel_inst_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod3impl_fk;
       citydb          postgres    false    283    7123    297            �           2606    34591 +   tunnel_installation tunnel_inst_lod4brep_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4brep_fk FOREIGN KEY (lod4_brep_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod4brep_fk;
       citydb          postgres    false    283    7131    298            �           2606    34606 +   tunnel_installation tunnel_inst_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_lod4impl_fk;
       citydb          postgres    false    283    7123    297            �           2606    34566 +   tunnel_installation tunnel_inst_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 U   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_objclass_fk;
       citydb          postgres    false    283    6682    244            �           2606    34571 )   tunnel_installation tunnel_inst_tunnel_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_installation
    ADD CONSTRAINT tunnel_inst_tunnel_fk FOREIGN KEY (tunnel_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;
 S   ALTER TABLE ONLY citydb.tunnel_installation DROP CONSTRAINT tunnel_inst_tunnel_fk;
       citydb          postgres    false    283    6946    277            �           2606    34411    tunnel tunnel_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod1msrf_fk;
       citydb          postgres    false    277    7131    298            �           2606    34431    tunnel tunnel_lod1solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod1solid_fk;
       citydb          postgres    false    277    7131    298            �           2606    34416    tunnel tunnel_lod2msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2msrf_fk FOREIGN KEY (lod2_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod2msrf_fk;
       citydb          postgres    false    277    7131    298            �           2606    34436    tunnel tunnel_lod2solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod2solid_fk;
       citydb          postgres    false    277    7131    298            �           2606    34421    tunnel tunnel_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod3msrf_fk;
       citydb          postgres    false    277    7131    298            �           2606    34441    tunnel tunnel_lod3solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod3solid_fk;
       citydb          postgres    false    277    7131    298            �           2606    34426    tunnel tunnel_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 C   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod4msrf_fk;
       citydb          postgres    false    277    7131    298            �           2606    34446    tunnel tunnel_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 D   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_lod4solid_fk;
       citydb          postgres    false    277    7131    298            �           2606    34451    tunnel tunnel_objectclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_objectclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 F   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_objectclass_fk;
       citydb          postgres    false    277    6682    244            �           2606    34531 (   tunnel_opening tunnel_open_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 R   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_cityobject_fk;
       citydb          postgres    false    282    7112    295            �           2606    34551 &   tunnel_opening tunnel_open_lod3impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3impl_fk FOREIGN KEY (lod3_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_lod3impl_fk;
       citydb          postgres    false    282    7123    297            �           2606    34541 &   tunnel_opening tunnel_open_lod3msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod3msrf_fk FOREIGN KEY (lod3_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_lod3msrf_fk;
       citydb          postgres    false    282    7131    298            �           2606    34556 &   tunnel_opening tunnel_open_lod4impl_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4impl_fk FOREIGN KEY (lod4_implicit_rep_id) REFERENCES citydb.implicit_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_lod4impl_fk;
       citydb          postgres    false    282    7123    297            �           2606    34546 &   tunnel_opening tunnel_open_lod4msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_lod4msrf_fk FOREIGN KEY (lod4_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_lod4msrf_fk;
       citydb          postgres    false    282    7131    298            �           2606    34536 &   tunnel_opening tunnel_open_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel_opening
    ADD CONSTRAINT tunnel_open_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 P   ALTER TABLE ONLY citydb.tunnel_opening DROP CONSTRAINT tunnel_open_objclass_fk;
       citydb          postgres    false    282    6682    244            �           2606    34401    tunnel tunnel_parent_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_parent_fk FOREIGN KEY (tunnel_parent_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;
 A   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_parent_fk;
       citydb          postgres    false    277    6946    277            �           2606    34406    tunnel tunnel_root_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.tunnel
    ADD CONSTRAINT tunnel_root_fk FOREIGN KEY (tunnel_root_id) REFERENCES citydb.tunnel(id) MATCH FULL ON UPDATE CASCADE;
 ?   ALTER TABLE ONLY citydb.tunnel DROP CONSTRAINT tunnel_root_fk;
       citydb          postgres    false    277    6946    277            �           2606    34356 0   waterboundary_surface waterbnd_srf_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 Z   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterbnd_srf_cityobject_fk;
       citydb          postgres    false    275    7112    295            �           2606    34366 -   waterboundary_surface waterbnd_srf_lod2srf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod2srf_fk FOREIGN KEY (lod2_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterbnd_srf_lod2srf_fk;
       citydb          postgres    false    275    7131    298            �           2606    34371 -   waterboundary_surface waterbnd_srf_lod3srf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod3srf_fk FOREIGN KEY (lod3_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterbnd_srf_lod3srf_fk;
       citydb          postgres    false    275    7131    298            �           2606    34376 -   waterboundary_surface waterbnd_srf_lod4srf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_lod4srf_fk FOREIGN KEY (lod4_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 W   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterbnd_srf_lod4srf_fk;
       citydb          postgres    false    275    7131    298            �           2606    34361 .   waterboundary_surface waterbnd_srf_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterboundary_surface
    ADD CONSTRAINT waterbnd_srf_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 X   ALTER TABLE ONLY citydb.waterboundary_surface DROP CONSTRAINT waterbnd_srf_objclass_fk;
       citydb          postgres    false    275    6682    244            �           2606    34346 0   waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk FOREIGN KEY (waterboundary_surface_id) REFERENCES citydb.waterboundary_surface(id) MATCH FULL ON UPDATE CASCADE ON DELETE CASCADE;
 Z   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf DROP CONSTRAINT waterbod_to_waterbnd_fk;
       citydb          postgres    false    274    6923    275            �           2606    34351 1   waterbod_to_waterbnd_srf waterbod_to_waterbnd_fk1    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf
    ADD CONSTRAINT waterbod_to_waterbnd_fk1 FOREIGN KEY (waterbody_id) REFERENCES citydb.waterbody(id) MATCH FULL ON UPDATE CASCADE;
 [   ALTER TABLE ONLY citydb.waterbod_to_waterbnd_srf DROP CONSTRAINT waterbod_to_waterbnd_fk1;
       citydb          postgres    false    274    6913    273            �           2606    34306 !   waterbody waterbody_cityobject_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_cityobject_fk FOREIGN KEY (id) REFERENCES citydb.cityobject(id) MATCH FULL ON UPDATE CASCADE;
 K   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_cityobject_fk;
       citydb          postgres    false    273    7112    295            �           2606    34311    waterbody waterbody_lod0msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod0msrf_fk FOREIGN KEY (lod0_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 I   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod0msrf_fk;
       citydb          postgres    false    273    7131    298            �           2606    34316    waterbody waterbody_lod1msrf_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1msrf_fk FOREIGN KEY (lod1_multi_surface_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 I   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod1msrf_fk;
       citydb          postgres    false    273    7131    298            �           2606    34321     waterbody waterbody_lod1solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod1solid_fk FOREIGN KEY (lod1_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 J   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod1solid_fk;
       citydb          postgres    false    273    7131    298            �           2606    34326     waterbody waterbody_lod2solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod2solid_fk FOREIGN KEY (lod2_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 J   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod2solid_fk;
       citydb          postgres    false    273    7131    298            �           2606    34331     waterbody waterbody_lod3solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod3solid_fk FOREIGN KEY (lod3_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 J   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod3solid_fk;
       citydb          postgres    false    273    7131    298            �           2606    34336     waterbody waterbody_lod4solid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_lod4solid_fk FOREIGN KEY (lod4_solid_id) REFERENCES citydb.surface_geometry(id) MATCH FULL ON UPDATE CASCADE;
 J   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_lod4solid_fk;
       citydb          postgres    false    273    7131    298            �           2606    34341    waterbody waterbody_objclass_fk    FK CONSTRAINT     �   ALTER TABLE ONLY citydb.waterbody
    ADD CONSTRAINT waterbody_objclass_fk FOREIGN KEY (objectclass_id) REFERENCES citydb.objectclass(id) MATCH FULL ON UPDATE CASCADE;
 I   ALTER TABLE ONLY citydb.waterbody DROP CONSTRAINT waterbody_objclass_fk;
       citydb          postgres    false    273    6682    244                  x������ � �      �      x������ � �      �      x������ � �            x������ � �           x��Xm�� �M�1��=Ag<NL����CH۽}!�� +vv����!-'R�C����=�f���zR�_?I���"|������!޹���vzdM��������y�iDe��]g���#��D��g��&��|���`���}UM"/�M?�'�=V;N''�.s�}8xX��x	�&���u4.7}4kV��A`�c��݂x��0� "^��<���Nm�߯��F����u"�O�d�h��~M�ȪB�J���/������1�|��$�� �{ �k �[ � �����ښXB�ep�!@�$T�����9�6�z�67��j�j�2���&���Uӝ�D0|;�g�C7]�R�?]�HE7������&
����XCc�P�h�P4T((��F
A#���B0h��m�&۠�~��}��sNj���]�Jl�}ꚳ?�ˬFU�F�ycB��-BQB⦖�JA, ��;(Q��]������}w�9C���o���j�6o�MBEF_"�V���1te2��S�,.cV:v�����}Ңm4��i�$�?O��â�ϊ�p!T�*\.�9��5�1�P��f��B��U2�6(�ء\!�4��)��T�#�;2�cJ)�z���m�nÀw.�*�P)��SXϧ6��DPA����s��ɐ�<'!lĐSa�I�/����i%Ҽ �L&�L~�鄫�"Ԣ"���c��Q?�y 1(V�$���]���|�C�hZ��A�b��6��k^ǻۜp���}�SB_�����!��SCƈU,	�1�PQ³�$@	g`���֙{�+b ����qee5~85~85>��.�A`�ʰ!�a��0��'8�o�0�N�e����&N	�}��ZLS�2����m��=��
��Z��\bL���i��q�����lcH�3�IF[t������)��e(� BE�>�P��s�J���{�a4�B��h\00�0���U���D���͋����?Xg0��g��~���v��      �      x������ � �            x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �            x������ � �             x������ � �            x������ � �      �      x������ � �      �      x������ � �      �   -   x�3627��,-ʳ�OO�JIM�J.*�rv��2�q��qqq �P
\            x������ � �      �      x������ � �      �      x������ � �      
      x������ � �      �      x������ � �            x������ � �         �   x���ێ�0�kx
�&���뻘4����C�j��� `)	W���C�*+������ST7l�A�̝L9rR�����3+�՞�!�Q���� �}�q�B_s���i_�7��f*q[�֐M��Lst���4��7B!�8o��e��(���8�Ä=Z�CA���N���|�Eq,�r�x��Q��[Uf�`A�~��u]W���I�.���j���C��e{πs���;��Uw����	u�L      �      x������ � �      �      x������ � �      �   ^  x��X[s�8~&?f�`�G�i��I�L�n��3�ld�-F�M��~�t$,A(qƝ���t�aL����聕4�n�]�z/�<�{&O|����v�۷��FP� S�a�7L?�� ��̾�4(��60��v�zwCK*�ޑ��J��3�����T�x�?� Z��Lq�j���԰cd'��
�5�EEP�a��c�	's���T*�Ԣ4�g��E�vj�I��kޔh�mā���bZ�U#<D#j��	p2�3c#ꝼ陷.8l�w��i���z�г�`��m̅"v͏/i)-z�.X<�×���$+S��ۅ�<��~⬔y�y��=|��ׂ��Č��켇_j�3��X�I+o��o�I�{Rapۈ��Q�ک����"H	o!FB!�����^9�\�-z��W�Z
���+2V���"c��eODH43�X��XxR��Z���oԂS�ZE�Rw�� ��Zf7��z¾oӉ��2��|�� -��B^��ҿ�Z���;��\������8g�qާ��~Bf��-��d�����X�Ry7Ok��Vf��Z��C����03���l}����{��@���~����\��
�HoU�;��ܩ��agk�.a�9���?s��B1���6�z���_AU5N���o�&[5�O����)'k^��T|�[�9qUU����O�<���!����LM,�&^����a@�0����<���H1��x��I�T���ۂ��l�=PA�F���9	�\(q�R˶����T�x�-����ce��u�g�e��pAYu�)`f!��91F�<6���0��a���G�*'X�C`��V�ؤQ��������g��s���&��fe�㶪]Ƴ�QC�����Z�8�v.��$/�ڦ�n���8�{�e�ӭq���!^���~����;�K�(w���G����.�hϹl�5�N�]��d�o��b�TW�`�ȹ#�W���_-ҭĉ�k!%]C>����0���J�Y�쩟?�4e	9R���m��:@b�`����f창<��7�@���x!/1�BCz�0��G�t4�&�*�O���2��sL@��g�1f�0�y�8u���:D�[���;��c\'�?f�EW�e�9�����KחL�� ���n2q�:�"='i���2H8A��:K��������Һr?�L�C��5h�ݳZ���b!"grC�!`ls.��.ʶym5�h4�/N9u��d���Z幠94���/��wG�h�2=R��Z��+8GI�gۜԬ�m�z�=6�c�6%/�	~b�N�|\Ih`w��	���wf�Q��-��\<��������&�q      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �            x������ � �            x������ � �            x������ � �      �      x������ � �            x������ � �            x������ � �      	      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �     