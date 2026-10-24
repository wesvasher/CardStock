---
title: Pages and page types
category: Writing
summary: Make a page, choose its type, and publish it when it's ready.
order: 1
---

Everything on your site is a page, and every page has a type. Find them all in [Pages](cardstock:pages).

## Make a page

1. Click **New Page…** at the bottom of [Pages](cardstock:pages), or **New Post** or **New Page** on the **Start** screen.
2. Type a title and choose a **Type**. CardStock gives the page its address from its type and title, like `/pages/contact/` or `/blog/pages/my-trip/`. See [page addresses](help:collections).
3. Click **Create** and start writing below the details.

CardStock saves as you type. There's no Save button to remember. You can change a page's type at any time with **Type** in the editor.

## Page types

| Type | What it is | Address |
|---|---|---|
| Static Page | A page on its own, like About or Contact. Link to it from the menu, the footer or other pages | `/pages/about/` |
| An item in a collection | A blog post, a product, a project, a video, … Each collection's items are listed on its main page | `/blog/pages/my-trip/`, `/work/pages/bridge/` |
| A collection's category | Your text, then the items you put in that category | `/blog/pages/travel/` |
| Link Menu | A list of links for a drop-down menu in the footer. Not a page of its own | — |

The **Type** menu lists your collections by name, such as **Post** under Blog and **Product** under Shop. Set up collections (and add new ones, like a Portfolio or Videos) in [Collections](cardstock:collections). See [Collections](help:collections).

**Home**, the page for broken links (404), **Search** and **Template** are special static pages. Every site has them, and their type can't change. Template shows every part of your style in the preview and is never published. See [Change fonts, colors and layout](help:theming). Each collection's **main page** is special too: it lists the collection's items under its own text, and goes away only when you delete the collection.

## Categories

An item can be in several categories of its collection.

1. Make the category page first: choose the collection's category (like **Blog Category**) as the type, or click **New Category…** in [Collections](cardstock:collections). Its text shows above the list.
2. On the item, click the **Categories** menu and tick the ones it belongs in. **New … Category…** in the same menu makes one without leaving the page.

Category pages fill themselves in. Drafts are left out until you publish them. To group pages across collections, use [tags](help:tags).

## Selling with a Product page

Your site is plain web pages, so it can't take payments itself. Make a checkout link with a service such as Stripe Payment Links, Gumroad, Etsy, Shopify or PayPal, and paste it into **Buy link**. The Buy button opens it in a new tab. **Button** changes the button's text; it says **Buy Now** if you leave it empty. Any collection can sell: turn on **Price and Buy button** in its settings.

## The details above the text

| Field | Types | What it does |
|---|---|---|
| Title | All | The heading and the name in lists |
| Layout | All but Link Menu | How the page is arranged. See [Page layouts](help:layouts) |
| Draft | All but Link Menu | Hides it from the published site. It still shows in the preview |
| Date | Items of dated collections | Orders items by time |
| Price, Buy link, Button | Items of selling collections | What it costs and where the Buy button goes |
| Video | Items of video collections | A YouTube or Vimeo link, or a video file, played at the top |
| Categories | Items | The category pages it's listed on |
| Summary | All but Link Menu | A short description for lists and search engines |
| Tags | Most pages | Topics that group pages across collections. Type one and press Return, or pick one from the tag menu. See [Tags](help:tags) |
| Cover | All but Link Menu | An image path such as `/media/posts/my-trip/beach.jpg` |

> New items in dated collections, like blog posts, start as **drafts**, so you can work on them before anyone sees them. Turn **Draft** off when the post is ready, then publish.

## Delete a page

Open it and click **Move to Trash…** at the bottom of the editor. The Markdown file goes to your Mac's Trash. Its images stay on the [Files](help:files) page until you delete them there. Home, the 404 page, Search, Template and collection main pages can't be deleted.

## Sites made before page types

Older sites kept posts in `posts/` and portfolio projects in `projects/`. When you open one, CardStock moves them all into `pages/` once:

- Posts become **Blog Posts**.
- Projects become **Static Pages**. Their old `/portfolio/` addresses redirect to the new ones, and a menu link named **Portfolio** is removed.

> If you use CardStock on two Macs, update both and get the latest from GitHub on each before you open the site. Otherwise both Macs make the same move.
