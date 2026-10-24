---
title: Ways to publish your website
category: Publishing
summary: Your options for putting the site online, and what happens when you publish.
order: 0
---

CardStock turns your posts and pages into a finished website made of plain HTML files, in the `public` folder inside your site folder. There are a few ways to put it online.

## GitHub and Cloudflare Pages (recommended)

Publishing is one button, and your site is backed up with its full history.

1. **Edit your site.** Changes save automatically on this Mac as you type.
2. **Publish.** CardStock generates the flat HTML, saves a snapshot of your changes, picks up anything published from your other Macs, and sends it all to your repository on GitHub.
3. **Your host updates the live site.** Cloudflare Pages notices the new snapshot on GitHub and updates your website, usually within a minute.

To set it up: [connect to GitHub](help:connect-github), then [host on Cloudflare Pages](help:cloudflare). You only do this once per site. It also lets you [work on another Mac](help:another-mac).

## Another host that deploys from GitHub

Netlify, GitHub Pages and similar hosts work the same way as Cloudflare Pages: no build command, and publish the `public` folder. Link the site to GitHub, then point the host at your repository.

## Upload the files yourself

No GitHub needed. Choose **Site → Generate Flat HTML** and upload everything inside `public` to any web host. See [Use CardStock without GitHub](help:without-github).

## Only on this Mac

You don't have to publish at all. The preview always shows the latest version, and the site stays private on this Mac until you're ready.

Ready to send changes? See [Publish your site](help:publish).
