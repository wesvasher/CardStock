---
title: Pages and page types
category: Writing
summary: Make a page, choose its type, and publish it when it's ready.
order: 1
---

Everything on your site is a page, and every page has a type. Find them all in [Pages](cardstock:pages).

## Make a page

1. Click **New Page…** at the bottom of [Pages](cardstock:pages), or **New Post** or **New Page** on the **Start** screen.
2. Type a title and choose a **Type**. The window shows the address it will have, such as `/posts/my-trip/`.
3. Click **Create** and start writing below the details.

CardStock saves as you type. There's no Save button to remember. You can change a page's type at any time with **Type** in the editor.

## Page types

| Type | What it is | Address |
|---|---|---|
| Static Page | A page on its own, like About or Contact. Link to it from the menu, the footer or other pages | `/about/` |
| Blog Post | Dated, listed newest first on the home page and in the RSS feed, and on the blog categories you choose | `/posts/my-trip/` |
| Blog Category | Your text, then every blog post in that category, newest first | `/blog/travel/` |
| Product | Something you sell: a price and a Buy button that goes to your checkout link | `/shop/blue-mug/` |
| Shop Category | Your text, then every product in that category | `/shop/cups/` |
| Link Menu | A list of links for a drop-down menu in the footer. Not a page of its own | — |

**Home**, the page for broken links (404) and **Template** are special static pages. Every site has them, and their type can't change. Template shows every part of your style in the preview and is never published. See [Change fonts, colors and layout](help:theming).

When there's at least one product, `/shop/` lists them all. Add it to your menu in [Top Navigation Bar](cardstock:top-bar) in Configuration.

## Categories

A blog post or product can be in several categories.

1. Make the category page first: a **Blog Category** for posts, a **Shop Category** for products. Its text shows above the list.
2. On the post or product, click the **Categories** menu and tick the ones it belongs in. **New Blog Category…** (or **New Shop Category…**) in the same menu makes one without leaving the page.

Category pages fill themselves in. Drafts are left out until you publish them.

## Selling with a Product page

Your site is plain web pages, so it can't take payments itself. Make a checkout link with a service such as Stripe Payment Links, Gumroad, Etsy, Shopify or PayPal, and paste it into **Buy link**. The Buy button opens it in a new tab. **Button** changes the button's text; it says **Buy Now** if you leave it empty.

## The details above the text

| Field | Types | What it does |
|---|---|---|
| Title | All | The heading and the name in lists |
| Layout | All but Link Menu | How the page is arranged. See [Page layouts](help:layouts) |
| Draft | All but Link Menu | Hides it from the published site. It still shows in the preview |
| Date | Blog Post | Orders posts, newest first |
| Price, Buy link, Button | Product | What it costs and where the Buy button goes |
| Categories | Blog Post, Product | The category pages it's listed on |
| Summary | All but Link Menu | A short description for lists and search engines |
| Tags | Blog Post | Comma-separated topics |
| Cover | All but Link Menu | An image path such as `/media/posts/my-trip/beach.jpg` |

> New blog posts start as **drafts**, so you can work on them before anyone sees them. Turn **Draft** off when the post is ready, then publish.

## Delete a page

Open it and click **Move to Trash…** at the bottom of the editor. The Markdown file goes to your Mac's Trash. Its images stay on the [Files](help:files) page until you delete them there. The Home page and the 404 page can't be deleted.

## Sites made before page types

Older sites kept posts in `posts/` and portfolio projects in `projects/`. When you open one, CardStock moves them all into `pages/` once:

- Posts become **Blog Posts** and keep their addresses.
- Projects become **Static Pages** at `/<name>/`. Their old `/portfolio/` addresses redirect to the new ones, and a menu link named **Portfolio** is removed.

> If you use CardStock on two Macs, update both and get the latest from GitHub on each before you open the site. Otherwise both Macs make the same move.
