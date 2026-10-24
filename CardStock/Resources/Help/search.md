---
title: Add search to your site
category: Writing
summary: A search page, plus search boxes you can put in any page.
order: 8
---

Every site has a **Search** page at `/search/`. Visitors type in its search field and matching pages show as they type, with the words they searched for highlighted. It works on its own: there's no search service, account or cost, and searches stay in the visitor's browser.

## Link to the search page

- Open [Search](cardstock:search) in Configuration and click **Add Search to the Top Bar**, or add a link to `/search/` yourself in [Top Navigation Bar](cardstock:top-bar) or [Footer](cardstock:footer). The page menu next to a link's address lists **Search** too.
- To open the page with a search already done, add `?q=` and the words, such as `/search/?q=soup`.

## Put a search box in a page

1. Open a page in [Pages](cardstock:pages).
2. Click where the box should go, on its own line.
3. Click the magnifying glass in the formatting bar.

That adds a `<!-- search -->` line, highlighted in the editor. On your site it shows a search field; searching from it opens the Search page with the results.

## Settings

In [Search](cardstock:search) in Configuration:

- **Search this site** turns search on or off. Off leaves out the Search page and every search box.
- **Find** picks which kinds of pages can be found: pages, blog posts, products and categories. Drafts are never found on your live site, and Home, the 404 page and link menus are left out.
- **Search Field** sets the text shown in an empty field and the button's text.

The **Search** page is in [Pages](cardstock:pages) like Home. Its text shows above the search field, so you can change the title or add a line about what's on the site. It can't be deleted, but you can turn search off. Its design is `theme/search.html` in your site folder.

> Search looks through each page's title, summary, tags, categories and the start of its text. When you publish, CardStock writes the list it searches to `search.json`.
