/* Mold a Wish — where the community map lives.
 *
 * Empty values: the page runs as before (each visitor only sees their own krathong, and the page says so).
 * Filled in: the shared community map, release, the 3D river with everyone's krathongs, and Realtime.
 *
 *   supabaseUrl             the "Mold a Wish" project URL, e.g. "https://<project-ref>.supabase.co"
 *   supabasePublishableKey  its PUBLISHABLE key (sb_publishable_…). Never a secret key, service-role key or DB password.
 *   publicSiteUrl           where the page is published (needed for "คัดลอกลิงก์กระทง"; localhost is never used as a public link)
 *   gaMeasurementId         Google Analytics 4 web stream "Mold a Wish — Production" (public by design; loads only after consent). Empty: no analytics.
 *
 * The database: supabase/migrations/*.sql, applied in file-name order.
 */
window.LK_CONFIG = {
  supabaseUrl: "https://tfosanmpxwvkgsjdggdo.supabase.co",
  supabasePublishableKey: "sb_publishable_HEwo-P-_BfNlRxWWOn6TMA_rjJr56Op",
  publicSiteUrl: "https://fy0ung.github.io/mold-a-wish/",
  gaMeasurementId: "G-TG2E2GD2L9",
};
