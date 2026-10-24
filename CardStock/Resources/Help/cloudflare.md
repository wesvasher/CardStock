---
title: Host on Cloudflare Pages
category: Publishing
summary: Put your site online for free. You only do this once.
order: 3
---

Cloudflare Pages watches your GitHub repository and updates your website each time you publish. First [connect to GitHub](help:connect-github).

1. Sign in to [Cloudflare](https://dash.cloudflare.com) (a free account works).
2. Go to **Workers & Pages → Create → Pages → Connect to Git**.
3. Connect your GitHub account and choose your site's repository.
4. Use these build settings:
   - **Build command:** leave empty
   - **Build output directory:** `public`
5. Click **Save and Deploy**.
6. Copy the address Cloudflare gives you, such as `my-site.pages.dev`, and paste it into **Web address** in [Site Details](cardstock:site-details).

From now on, each **Publish** updates the live site within a minute or so.

## Your own domain

In Cloudflare, open the project, go to **Custom domains** and follow the steps. Then update **Web address** in Configuration → Site Details.

Other hosts that deploy from GitHub (Netlify, GitHub Pages and others) work the same way: no build command, and publish the `public` folder.
