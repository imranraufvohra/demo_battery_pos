/** Allow the marketing site to embed the demo in an iframe. Do not set X-Frame-Options. */
const ancestors = process.env.NEXT_PUBLIC_DEMO_MODE === "true"
  ? "'self' https://www.makemystore.online https://makemystore.online"
  : "'self'";

module.exports = {
  async headers() {
    return [{ source: "/(.*)", headers: [{ key: "Content-Security-Policy", value: `frame-ancestors ${ancestors}` }] }];
  },
};
