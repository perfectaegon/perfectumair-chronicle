const loginPanel = document.getElementById("login-panel");
const dashboardPanel = document.getElementById("dashboard-panel");
const loginForm = document.getElementById("login-form");
const loginStatus = document.getElementById("login-status");
const logoutButton = document.getElementById("logout-button");
const publishStatus = document.getElementById("publish-status");
const archiveList = document.getElementById("archive-list");
const archiveCount = document.getElementById("archive-count");
const archiveTemplate = document.getElementById("archive-item-template");

const articleForm = document.getElementById("article-form");
const photoForm = document.getElementById("photo-form");
const videoForm = document.getElementById("video-form");

const TYPE_LABELS = {
  article: "Dispatch",
  photo: "Photograph",
  video: "Film",
};

function setStatus(el, message, type) {
  el.textContent = message;
  el.className = "status" + (type ? ` ${type}` : "");
}

function showTab(tab) {
  document.querySelectorAll(".publish-tab").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tab);
  });
  articleForm.classList.toggle("hidden", tab !== "article");
  photoForm.classList.toggle("hidden", tab !== "photo");
  videoForm.classList.toggle("hidden", tab !== "video");
}

async function checkSession() {
  try {
    const res = await fetch("/admin/api/session");
    const data = await res.json();
    if (data.authenticated) {
      loginPanel.classList.add("hidden");
      dashboardPanel.classList.remove("hidden");
      loadArchive();
    }
  } catch {
    /* stay on login */
  }
}

loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  setStatus(loginStatus, "Signing in...", "");

  const password = document.getElementById("password-input").value;
  try {
    const res = await fetch("/admin/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    const data = await res.json();
    if (!res.ok) {
      setStatus(loginStatus, data.error || "Login failed", "err");
      return;
    }
    loginPanel.classList.add("hidden");
    dashboardPanel.classList.remove("hidden");
    setStatus(loginStatus, "");
    loadArchive();
  } catch {
    setStatus(loginStatus, "Could not reach server", "err");
  }
});

logoutButton.addEventListener("click", async () => {
  await fetch("/admin/api/logout", { method: "POST" });
  dashboardPanel.classList.add("hidden");
  loginPanel.classList.remove("hidden");
  loginForm.reset();
});

document.querySelectorAll(".publish-tab").forEach((tab) => {
  tab.addEventListener("click", () => showTab(tab.dataset.tab));
});

articleForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  setStatus(publishStatus, "Publishing dispatch...", "");

  const payload = {
    title: document.getElementById("article-title").value.trim(),
    excerpt: document.getElementById("article-excerpt").value.trim(),
    body: document.getElementById("article-body").value.trim(),
  };

  try {
    const res = await fetch("/admin/api/article", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) {
      setStatus(publishStatus, data.error || "Failed to publish", "err");
      return;
    }
    articleForm.reset();
    setStatus(publishStatus, "Dispatch published to the front page.", "ok");
    loadArchive();
  } catch {
    setStatus(publishStatus, "Could not reach server", "err");
  }
});

function setupDropzone(dropzoneId, inputId, filenameId) {
  const dropzone = document.getElementById(dropzoneId);
  const input = document.getElementById(inputId);
  const filenameEl = document.getElementById(filenameId);

  dropzone.addEventListener("dragover", (e) => {
    e.preventDefault();
    dropzone.classList.add("dragover");
  });
  dropzone.addEventListener("dragleave", () => dropzone.classList.remove("dragover"));
  dropzone.addEventListener("drop", (e) => {
    e.preventDefault();
    dropzone.classList.remove("dragover");
    if (e.dataTransfer.files.length) {
      input.files = e.dataTransfer.files;
      filenameEl.textContent = e.dataTransfer.files[0].name;
    }
  });
  input.addEventListener("change", () => {
    filenameEl.textContent = input.files[0] ? input.files[0].name : "";
  });
}

setupDropzone("photo-dropzone", "photo-input", "photo-filename");
setupDropzone("video-dropzone", "video-input", "video-filename");

function isHeicPhoto(file) {
  const name = file.name.toLowerCase();
  const type = (file.type || "").toLowerCase();
  return (
    type === "image/heic" ||
    type === "image/heif" ||
    name.endsWith(".heic") ||
    name.endsWith(".heif")
  );
}

async function preparePhotoFile(file) {
  if (!isHeicPhoto(file) || typeof heic2any !== "function") {
    return file;
  }

  setStatus(publishStatus, "Converting iPhone photo...", "");

  const converted = await heic2any({
    blob: file,
    toType: "image/jpeg",
    quality: 0.92,
  });

  const blob = Array.isArray(converted) ? converted[0] : converted;
  const baseName = file.name.replace(/\.[^.]+$/, "") || "photo";
  return new File([blob], `${baseName}.jpg`, {
    type: "image/jpeg",
    lastModified: Date.now(),
  });
}

async function uploadMedia(form, type, titleId, captionId, inputId) {
  const fileInput = document.getElementById(inputId);
  if (!fileInput.files.length) {
    setStatus(publishStatus, "Please choose a file first", "err");
    return;
  }

  let file = fileInput.files[0];
  if (type === "photo") {
    try {
      file = await preparePhotoFile(file);
    } catch {
      setStatus(publishStatus, "Could not process this photo. Try again or use JPG/PNG.", "err");
      return;
    }
  }

  setStatus(publishStatus, "Uploading...", "");

  const formData = new FormData();
  formData.append("type", type);
  formData.append("file", file);
  formData.append("title", document.getElementById(titleId).value.trim());
  formData.append("caption", document.getElementById(captionId).value.trim());

  try {
    const res = await fetch("/admin/api/upload", {
      method: "POST",
      body: formData,
    });
    const data = await res.json();
    if (!res.ok) {
      setStatus(publishStatus, data.error || "Upload failed", "err");
      return;
    }
    form.reset();
    document.getElementById(inputId.replace("-input", "-filename")).textContent = "";
    setStatus(publishStatus, `${TYPE_LABELS[type]} published successfully.`, "ok");
    loadArchive();
  } catch {
    setStatus(publishStatus, "Could not reach server", "err");
  }
}

photoForm.addEventListener("submit", (e) => {
  e.preventDefault();
  uploadMedia(photoForm, "photo", "photo-title", "photo-caption", "photo-input");
});

videoForm.addEventListener("submit", (e) => {
  e.preventDefault();
  uploadMedia(videoForm, "video", "video-title", "video-caption", "video-input");
});

function formatDate(iso) {
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function renderArchiveItem(post) {
  const node = archiveTemplate.content.cloneNode(true);
  const preview = node.querySelector(".archive-preview");

  if (post.type === "photo" && post.filename) {
    const img = document.createElement("img");
    img.src = `/uploads/${post.filename}`;
    img.alt = post.title;
    preview.appendChild(img);
  } else if (post.type === "video") {
    preview.textContent = "🎬";
  } else {
    preview.textContent = "✒";
  }

  node.querySelector(".archive-type").textContent = TYPE_LABELS[post.type] || post.type;
  node.querySelector(".archive-title").textContent = post.title;
  node.querySelector(".archive-date").textContent = formatDate(post.published_at);

  const deleteBtn = node.querySelector(".btn-danger");
  deleteBtn.addEventListener("click", async () => {
    if (!confirm(`Remove "${post.title}" from the archive?`)) return;

    const res = await fetch(`/admin/api/posts/${post.id}`, { method: "DELETE" });
    if (res.ok) {
      loadArchive();
      setStatus(publishStatus, "Item removed.", "ok");
    } else {
      setStatus(publishStatus, "Could not remove item", "err");
    }
  });

  archiveList.appendChild(node);
}

async function loadArchive() {
  try {
    const res = await fetch("/admin/api/posts");
    const data = await res.json();
    const posts = data.posts || [];

    archiveList.innerHTML = "";
    archiveCount.textContent = `${posts.length} item${posts.length === 1 ? "" : "s"}`;
    posts.forEach(renderArchiveItem);
  } catch {
    archiveCount.textContent = "Could not load";
  }
}

checkSession();