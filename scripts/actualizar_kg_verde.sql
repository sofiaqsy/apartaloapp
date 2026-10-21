-- ─────────────────────────────────────────────────────────────────────────────
-- Actualizar los kg disponibles de un lote de café verde (15 kg → 52 kg)
--
-- El stock de café verde NO está en products: sale de
-- green_lots.current_kg, a través de products.green_lot_id.
-- Ejecutar consulta por consulta en el SQL Editor de Supabase.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) VER QUÉ HAY. Identifica el lote antes de tocar nada.
SELECT p.name            AS producto,
       p.slug,
       gl.id             AS green_lot_id,
       gl.lot_code,
       gl.initial_kg,
       gl.current_kg,
       gl.status
FROM       public.products p
JOIN       public.green_lots gl ON gl.id = p.green_lot_id
WHERE      p.green_lot_id IS NOT NULL
ORDER BY   p.name;


-- 2) ACTUALIZAR. Reemplaza el lot_code por el que viste arriba.
--    Se filtra además por current_kg = 15 como red de seguridad: si el valor
--    ya no es 15, no actualiza nada en vez de pisar un dato distinto.
UPDATE public.green_lots
SET    current_kg = 52,
       updated_at = now()
WHERE  lot_code   = 'REEMPLAZAR-LOT-CODE'
  AND  current_kg = 15;


-- 3) VERIFICAR que quedó en 52.
SELECT p.name AS producto, gl.lot_code, gl.initial_kg, gl.current_kg
FROM       public.products p
JOIN       public.green_lots gl ON gl.id = p.green_lot_id
WHERE      gl.lot_code = 'REEMPLAZAR-LOT-CODE';


-- ── Alternativa: actualizar por producto en vez de por lot_code ──────────────
-- Útil si conoces el nombre del café pero no el código del lote.
--
-- UPDATE public.green_lots gl
-- SET    current_kg = 52,
--        updated_at = now()
-- FROM   public.products p
-- WHERE  p.green_lot_id = gl.id
--   AND  p.slug = 'REEMPLAZAR-SLUG'
--   AND  gl.current_kg = 15;


-- ── Nota sobre initial_kg ───────────────────────────────────────────────────
-- current_kg es lo que queda; initial_kg es lo que entró. Si los 52 kg son
-- una reposición (llegó café nuevo) y no una corrección de un dato mal
-- cargado, conviene subir también initial_kg para que la trazabilidad
-- cuadre:
--
-- UPDATE public.green_lots
-- SET    current_kg = 52,
--        initial_kg = initial_kg + 37,   -- 52 - 15 = 37 kg que ingresaron
--        updated_at = now()
-- WHERE  lot_code = 'REEMPLAZAR-LOT-CODE';
