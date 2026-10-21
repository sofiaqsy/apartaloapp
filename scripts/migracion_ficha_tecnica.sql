-- ─────────────────────────────────────────────────────────────────────────────
-- Campo faltante para la etiqueta de MUESTRA (ficha técnica)
-- Verificado contra el esquema el 2026-09-08: no existe ninguna columna de
-- puntaje en el esquema público — el 85.5 del sitio web está harcodeado.
-- ─────────────────────────────────────────────────────────────────────────────

-- Puntaje SCA: va en el PRODUCTO, no en la finca — es la nota de catación de
-- un café específico (Blend 84, Geisha 87), no un atributo de la finca.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sca_score numeric(4,1);

COMMENT ON COLUMN public.products.sca_score IS
  'Puntaje de catación SCA (0-100, típicamente 80-90 en especialidad)';


-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT slug, name, sca_score
FROM   public.products
ORDER BY name;


-- ── Carga de puntajes ────────────────────────────────────────────────────────
-- Valores tomados de las etiquetas impresas: Blend 84, Geisha 87.
-- (Su promedio es 85.5 — el mismo número harcodeado en la página de la finca.)
--
-- OJO: revisar primero qué productos hay y con qué slug, porque abajo se
-- filtra por slug exacto:
--
--   SELECT slug, name FROM public.products ORDER BY name;

UPDATE public.products SET sca_score = 87.0 WHERE slug = 'geisha';
UPDATE public.products SET sca_score = 84.0 WHERE slug = 'omagua-cafe-villa-rica-blend';

-- Pendientes: 'essential' y 'obata' — no tengo su puntaje.
-- UPDATE public.products SET sca_score = ??.? WHERE slug = 'essential';
-- UPDATE public.products SET sca_score = ??.? WHERE slug = 'obata';


-- ── Verificación final ───────────────────────────────────────────────────────
-- Los productos que queden en NULL todavía necesitan su puntaje.
SELECT slug, name, sca_score
FROM   public.products
ORDER BY sca_score NULLS FIRST, name;
