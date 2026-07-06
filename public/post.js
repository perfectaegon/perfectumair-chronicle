const headline = document.getElementById("article-headline");
const byline = document.getElementById("article-byline");
const body = document.getElementById("article-body");
const page = document.getElementById("article-page");
const notFound = document.getElementById("not-found");
const yearEl = document.getElementById("year");

function formatDate(iso) {
  const date = new Date(iso);
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

function getPostId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("id");
}

async function loadArticle() {
  yearEl.textContent = new Date().getFullYear();

  const id = getPostId();
  if (!id) {
    page.classList.add("hidden");
    notFound.classList.remove("hidden");
    return;
  }

  try {
    const response = await fetch(`/api/posts/${id}`);
    if (!response.ok) throw new Error("Not found");

    const data = await response.json();
    const post = data.post;

    if (post.type !== "article") {
      throw new Error("Not an article");
    }

    document.title = `${post.title} · The ok.mairr Chronicle`;
    headline.textContent = post.title;
    byline.textContent = `By ok.mairr · ${formatDate(post.published_at)}`;
    body.textContent = post.body;
  } catch {
    page.classList.add("hidden");
    notFound.classList.remove("hidden");
  }
}

loadArticle();