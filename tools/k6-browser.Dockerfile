# k6 with a bundled Chromium, for the k6 *browser* module (Core Web Vitals).
# The stock grafana/k6 image has no browser; the browser module needs one.
# feed-k6-browser.sh builds this on demand.
FROM grafana/k6:latest
USER root
RUN apk add --no-cache chromium nss freetype harfbuzz ca-certificates ttf-freefont
ENV K6_BROWSER_HEADLESS=true
ENV K6_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium-browser
