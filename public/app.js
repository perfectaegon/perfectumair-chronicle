const articlesList = document.getElementById("articles-list");
const photosGrid = document.getElementById("photos-grid");
const videosList = document.getElementById("videos-list");
const leadStory = document.getElementById("lead-story");
const leadHeadline = document.getElementById("lead-headline");
const leadByline = document.getElementById("lead-byline");
const leadExcerpt = document.getElementById("lead-excerpt");
const leadLink = document.getElementById("lead-link");
const emptyState = document.getElementById("empty-state");
const contentColumns = document.getElementById("content-columns");
const dateline = document.getElementById("dateline");
const yearEl = document.getElementById("year");

const articleTemplate = document.getElementById("article-card-template");
const photoTemplate = document.getElementById("photo-card-template");
const videoTemplate = document.getElementById("video-card-template");

let allPosts = [];
let activeFilter = "all";

function formatDate(iso) {
  const date = new Date(iso);
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

function formatShortDate(iso) {
  const date = new Date(iso);
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function setDateline() {
  const now = new Date();
  dateline.textContent = now.toLocaleDateString("en-US", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  yearEl.textContent = now.getFullYear();
}

function renderArticle(post) {
  const node = articleTemplate.content.cloneNode(true);
  const card = node.querySelector(".story-card");
  card.dataset.type = "article";

  node.querySelector(".story-title").textContent = post.title;
  node.querySelector(".story-date").textContent = formatShortDate(post.published_at);
  node.querySelector(".story-excerpt").textContent = post.excerpt || post.body.slice(0, 160);
  node.querySelector(".story-link").href = `/post.html?id=${post.id}`;

  articlesList.appendChild(node);
}

function renderPhoto(post) {
  const node = photoTemplate.content.cloneNode(true);
  const card = node.querySelector(".photo-card");
  card.dataset.type = "photo";

  const img = node.querySelector("img");
  img.src = `/uploads/${post.filename}`;
  img.alt = post.title || post.caption || "Photograph";

  node.querySelector(".photo-link").href = `/uploads/${post.filename}`;
  node.querySelector(".photo-title").textContent = post.title;
  node.querySelector(".photo-date").textContent = formatShortDate(post.published_at);

  photosGrid.appendChild(node);
}

function renderVideo(post) {
  const node = videoTemplate.content.cloneNode(true);
  const card = node.querySelector(".video-card");
  card.dataset.type = "video";

  const video = node.querySelector("video");
  video.src = `/uploads/${post.filename}`;
  video.setAttribute("aria-label", post.title);

  node.querySelector(".video-title").textContent = post.title;
  node.querySelector(".video-caption").textContent = post.caption || "";
  node.querySelector(".video-date").textContent = formatShortDate(post.published_at);

  videosList.appendChild(node);
}

function setLeadStory(article) {
  if (!article) {
    leadStory.classList.add("hidden");
    return;
  }

  leadStory.classList.remove("hidden");
  leadHeadline.textContent = article.title;
  leadByline.textContent = `By ok.mairr · ${formatDate(article.published_at)}`;
  leadExcerpt.textContent = article.excerpt || article.body.slice(0, 220);
  leadLink.href = `/post.html?id=${article.id}`;
}

function applyFilter(filter) {
  activeFilter = filter;

  document.querySelectorAll(".section-tab").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.filter === filter);
  });

  const show = (type) => filter === "all" || filter === type;

  leadStory.classList.toggle("filter-hidden", filter !== "all" && filter !== "article");
  contentColumns.classList.toggle("hidden", filter === "all" ? false : false);

  document.querySelectorAll(".articles-column").forEach((el) => {
    el.classList.toggle("filter-hidden", !show("article"));
  });
  document.querySelectorAll(".photos-column").forEach((el) => {
    el.classList.toggle("filter-hidden", !show("photo"));
  });
  document.querySelectorAll(".videos-column").forEach((el) => {
    el.classList.toggle("filter-hidden", !show("video"));
  });
}

function renderPosts(posts) {
  articlesList.innerHTML = "";
  photosGrid.innerHTML = "";
  videosList.innerHTML = "";

  const articles = posts.filter((p) => p.type === "article");
  const photos = posts.filter((p) => p.type === "photo");
  const videos = posts.filter((p) => p.type === "video");

  if (posts.length === 0) {
    emptyState.classList.remove("hidden");
    contentColumns.classList.add("hidden");
    leadStory.classList.add("hidden");
    return;
  }

  emptyState.classList.add("hidden");
  contentColumns.classList.remove("hidden");

  setLeadStory(articles[0]);
  articles.forEach((post, i) => {
    if (i === 0 && activeFilter === "all") return;
    renderArticle(post);
  });
  if (articles.length === 1 && activeFilter !== "all") {
    renderArticle(articles[0]);
  }

  photos.forEach(renderPhoto);
  videos.forEach(renderVideo);

  applyFilter(activeFilter);
}

async function loadPosts() {
  try {
    const response = await fetch("/api/posts");
    const data = await response.json();
    allPosts = data.posts || [];
    renderPosts(allPosts);
  } catch (err) {
    emptyState.classList.remove("hidden");
    contentColumns.classList.add("hidden");
    leadStory.classList.add("hidden");
    emptyState.querySelector("h2").textContent = "Could not load edition";
    emptyState.querySelector("p").textContent = "Please try again shortly.";
  }
}

document.querySelectorAll(".section-tab").forEach((tab) => {
  tab.addEventListener("click", () => applyFilter(tab.dataset.filter));
});

setDateline();
loadPosts();