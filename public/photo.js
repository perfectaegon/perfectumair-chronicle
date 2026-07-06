const headline = document.getElementById("photo-headline");
const caption = document.getElementById("photo-caption");
const byline = document.getElementById("photo-byline");
const image = document.getElementById("photo-image");
const download = document.getElementById("photo-download");
const page = document.getElementById("photo-page");
const notFound = document.getElementById("not-found");
const closeButton = document.getElementById("photo-close");

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

function closePhoto() {
  if (window.history.length > 1) {
    window.history.back();
    return;
  }

  window.location.href = "/";
}

async function loadPhoto() {
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

    if (post.type !== "photo" || !post.filename) {
      throw new Error("Not a photo");
    }

    const imageUrl = `/uploads/${post.filename}`;
    const downloadName = post.original_name || post.filename;

    document.title = `${post.title} · The ok.mairr Chronicle`;
    headline.textContent = post.title;
    caption.textContent = post.caption || "";
    caption.classList.toggle("hidden", !post.caption);
    byline.textContent = `By ok.mairr · ${formatDate(post.published_at)}`;
    image.src = imageUrl;
    image.alt = post.title || post.caption || "Photograph";
    download.href = imageUrl;
    download.setAttribute("download", downloadName);
  } catch {
    page.classList.add("hidden");
    notFound.classList.remove("hidden");
  }
}

closeButton.addEventListener("click", closePhoto);
loadPhoto();