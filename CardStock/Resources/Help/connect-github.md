---
title: Connect to GitHub
category: Publishing
summary: Step by step, from token to linked site.
order: 1
---

GitHub stores your site and its history. Once linked, publishing is one button. You'll need a free [GitHub account](https://github.com/signup).

## 1. Make a token

A token is a password just for CardStock.

1. Open [Publishing](cardstock:publishing) and click **Open GitHub Token Page…**.
2. On GitHub, check only **repo**. The page opens with it already checked and named CardStock.
3. Choose an expiration date, or **No expiration**.
4. Click **Generate token** and copy it. It starts with `ghp_`.

> GitHub shows the token only once. If you lose it, make a new one.

## 2. Sign in

1. Paste the token into **Paste your personal access token here**.
2. Click **Sign In to GitHub**.

The token is kept in your Mac's Keychain, never in the site folder. CardStock remembers the account, so you sign in once per Mac.

## 3. Link the site

Starting from scratch? Check the repository name (CardStock suggests one from your site's title) and click **Create Repository and Link**. That one click creates the repository on GitHub, links it to this site and uploads everything. Keep **Private repository** on unless you want others to see your files and drafts.

Already made an *empty* repository on GitHub? Open **Link it instead**, type `owner/name` and click **Link Existing Repository**.

CardStock uploads your site. Next: [host it on Cloudflare Pages](help:cloudflare).

## More than one GitHub account

A Mac can be signed in to several accounts, for example yours and a family member's, each publishing their own site.

- Add accounts in **CardStock → Settings… → GitHub**. Make the token while signed in to GitHub as that person.
- Each site remembers which account publishes it from this Mac. Change it with **Publishing as** on the site's [Publishing](cardstock:publishing) page.
- The **default** account is used for new links and for **Open from GitHub…**.

> Publishing needs Apple's Command Line Tools. If they're missing, CardStock offers to install them.
