CREATE OR REPLACE FUNCTION zoom_level_grid(
    zoom_level INTEGER
) RETURNS TABLE (
    tile_z INTEGER,
    tile_x INTEGER,
    tile_y INTEGER,
    tile_geometry GEOMETRY
) AS $$
BEGIN
    RETURN QUERY
        WITH RECURSIVE tiles(x, y, z, e) AS (
            SELECT 0, 0, 0, XYZ_Extent(0, 0, 0, 0)
            UNION ALL
            SELECT x*2 + xx, y*2 + yy, z+1,
                   XYZ_Extent(x*2 + xx, y*2 + yy, z+1, 0)
            FROM tiles,
            (VALUES (0, 0), (0, 1), (1, 1), (1, 0)) as c(xx, yy)
            WHERE z < zoom_level
        )
        SELECT DISTINCT z, x, y, e FROM tiles WHERE z = zoom_level;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

DROP TABLE IF EXISTS grid_z9 CASCADE;
CREATE TABLE grid_z9 AS
SELECT tile_x AS x, tile_y AS y, tile_z AS z, tile_geometry AS geometry
FROM zoom_level_grid(9);

CREATE INDEX ON grid_z9 USING gist (geometry);

DROP TABLE IF EXISTS osm_landuse_split_polygon CASCADE;
CREATE TABLE osm_landuse_split_polygon AS
SELECT id, type, timestamp,
       ST_Intersection(p.geometry, grid.geometry) AS geometry
FROM osm_landuse_polygon AS p
LEFT OUTER JOIN grid_z9 AS grid ON (p.geometry && grid.geometry)
WHERE ST_Area(p.geometry) > 1000000000;

CREATE INDEX ON osm_landuse_split_polygon USING gist (geometry);
CREATE INDEX ON osm_landuse_split_polygon
USING btree (st_geohash(st_transform(st_setsrid(box2d(geometry)::geometry, 3857), 4326)));

SELECT UpdateGeometrySRID('osm_landuse_split_polygon','geometry', 3857);
