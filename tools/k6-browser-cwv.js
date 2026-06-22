// ShopLite Core Web Vitals journey for the k6 *browser* module.
//
// Unlike the protocol-level k6 script (which drives the JSON API and feeds the
// "ShopLite — k6 Performance" board), this one runs a REAL Chromium via
// `k6/browser`, so k6 automatically collects Web Vitals — LCP, INP, CLS, FCP,
// TTFB — and streams them to InfluxDB as `browser_web_vital_*` measurements.
// Those fill the "ShopLite — k6 Browser (Core Web Vitals)" dashboard.
//
// The same shopper funnel as the sitespeed journey:
//   catalog (index) -> product (+ add-to-cart interaction) -> cart -> checkout
// The click on the product page is what gives INP something to measure.
//
// Tunables (env): BASE_URL (default http://mock/), VUS, ITERATIONS.
import { browser } from 'k6/browser';

// k6's JS runtime has no global URL constructor, so join by hand.
const BASE = (__ENV.BASE_URL || 'http://mock/').replace(/\/?$/, '/');
const u = (path) => BASE + path.replace(/^\//, '');

export const options = {
  scenarios: {
    cwv: {
      executor: 'shared-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS || 8),
      maxDuration: '5m',
      options: { browser: { type: 'chromium' } },
    },
  },
  // SLOs as code: the run FAILS (exit 1) if a Core Web Vital busts Google's
  // "good" p75 threshold — this is the perf equivalent of an assertion, so the
  // same script doubles as a CI gate (locally and in k6 Cloud). Try
  // `SLOW=1 DELAY_MS=2200 ./tools/feed-k6-browser.sh` to watch them go red.
  thresholds: {
    'browser_web_vital_lcp': ['p(75)<2500'],  // Largest Contentful Paint
    'browser_web_vital_inp': ['p(75)<200'],   // Interaction to Next Paint (lab rarely has data → no-op)
    'browser_web_vital_cls': ['p(75)<0.1'],   // Cumulative Layout Shift
    'browser_web_vital_fcp': ['p(75)<1800'],  // First Contentful Paint
    'browser_web_vital_ttfb': ['p(75)<800'],  // Time To First Byte
  },
};

// Measure ONE page in its OWN browser context. k6 finalises a page's Web Vitals
// on close, tagged with that page's URL — and only the first page of a context
// gets instrumented, so each page needs a fresh context to land its own
// per-page series (index / product / cart / checkout). `interact` clicks
// Add-to-cart so INP has an interaction to measure.
async function measurePage(path, interact) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  try {
    await page.goto(u(path), { waitUntil: 'load' });
    if (interact) {
      try {
        await page.locator('#add-to-cart').click();
      } catch (e) {
        // button missing/renamed — still record the navigation vitals
      }
    }
    await page.waitForTimeout(400); // let LCP settle / INP register
  } finally {
    await ctx.close(); // closes the page too
  }
}

export default async function () {
  await measurePage('index.html', false);    // 1. Catalog (landing)
  await measurePage('product.html', true);    // 2. Product (+ add-to-cart → INP)
  await measurePage('cart.html', false);      // 3. Cart
  await measurePage('checkout.html', false);  // 4. Checkout
}
