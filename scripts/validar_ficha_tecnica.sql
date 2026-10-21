-- ─────────────────────────────────────────────────────────────────────────────
-- Validación de campos para la etiqueta de MUESTRA (ficha técnica del café)
-- Ejecutar en el SQL Editor de Supabase, consulta por consulta.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) ¿Existen "altura" y "puntaje CSA" en ALGUNA tabla?
--    Busca por nombre de columna en todo el esquema público.
SELECT table_name, column_name, data_type
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND (column_name ILIKE '%altitud%'  OR column_name ILIKE '%altura%'
    OR column_name ILIKE '%masl%'     OR column_name ILIKE '%elevation%'
    OR column_name ILIKE '%score%'    OR column_name ILIKE '%puntaje%'
    OR column_name ILIKE '%csa%'      OR column_name ILIKE '%cupping%')
ORDER BY table_name, column_name;


-- 2) Columnas reales de products (para comparar con el modelo Flutter)
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'products'
ORDER BY ordinal_position;


-- 3) ¿Cómo se llaman las tablas de proceso y secado?
SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND (table_name ILIKE '%process%' OR table_name ILIKE '%drying%'
    OR table_name ILIKE '%coffee%')
ORDER BY table_name;


-- 4) Valores usados en roast_operators.role (para saber cómo filtrar
--    "Productor" vs "Tostador" en la etiqueta)
SELECT role, count(*) AS operadores
FROM   public.roast_operators
GROUP BY role
ORDER BY operadores DESC;


-- 5) Fila completa tal como la imprimiría la etiqueta.
--    Cambiar el slug por el producto que quieras revisar.
SELECT
  p.name                                   AS nombre,
  array_to_string(p.blend_varieties, ', ') AS variedades,
  cv.name                                  AS variedad,
  crl.name                                 AS tostado,
  array_to_string(p.sensory_notes, ', ')   AS notas,
  f.name                                   AS finca,
  concat_ws(', ', f.location, f.city, f.country) AS origen,
  f.description                            AS finca_descripcion,
  p.detail                                 AS detalle,
  p.process_method_id,
  p.drying_method_id
FROM       public.products p
LEFT JOIN  public.farms                f   ON f.id   = p.farm_id
LEFT JOIN  public.coffee_varieties     cv  ON cv.id  = p.variety_id
LEFT JOIN  public.coffee_roast_levels  crl ON crl.id = p.roast_level_id
WHERE      p.slug = 'geisha';


-- 6) Productor y tostador asociados a la finca de ese producto
SELECT ro.name, ro.role, ro.instagram, ro.active
FROM       public.roast_operators ro
JOIN       public.products p ON p.farm_id = ro.farm_id
WHERE      p.slug = 'geisha'
ORDER BY   ro.role;


-- 7) ¿Qué tan completos están los datos en TODOS los productos?
--    Cuenta cuántos productos tienen cada campo vacío.
SELECT
  count(*)                                                   AS total,
  count(*) FILTER (WHERE p.sensory_notes IS NULL
                      OR cardinality(p.sensory_notes) = 0)   AS sin_notas,
  count(*) FILTER (WHERE p.variety_id      IS NULL)           AS sin_variedad,
  count(*) FILTER (WHERE p.roast_level_id  IS NULL)           AS sin_tostado,
  count(*) FILTER (WHERE p.process_method_id IS NULL)         AS sin_proceso,
  count(*) FILTER (WHERE p.farm_id         IS NULL)           AS sin_finca
FROM public.products p
WHERE p.status = 'active';
