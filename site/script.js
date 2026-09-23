const pathData = {
  guided: {
    label: "Recommended first run",
    title: "Open the launcher from elevated PowerShell.",
    description:
      "The launcher checks admin state, shows the current manifest status, and lets you run backup, verify, apply, revert, or individual tweak categories.",
    command: 'cd "<path-to-repo>"\n.\\launcher.ps1',
    steps: [
      "Clone or download this repo to a local folder.",
      "Right-click PowerShell and choose Run as Administrator.",
      "Run the command, then use [V] verify before applying anything.",
    ],
  },
  verify: {
    label: "Read-only confidence check",
    title: "Inspect the current state before changing the machine.",
    description:
      "Verification reports applied, drifted, and already-present states without mutating Windows.",
    command: 'cd "<path-to-repo>"\n.\\10 verify\\verify-tweaks.ps1',
    steps: [
      "Open Administrator PowerShell.",
      "Run the verify script from the repo root.",
      "Use the results to decide whether you need a specific phase or a rollback.",
    ],
  },
  aggressive: {
    label: "Maximum scripted tuning",
    title: "Apply the full stack only after reading the warnings.",
    description:
      "Apply Everything combines power, services, registry, GPU, network, cleanup, and Security Trade-off phases.",
    command: 'cd "<path-to-repo>"\n.\\APPLY-EVERYTHING.ps1',
    steps: [
      "Create the backup and restore point first.",
      "Read GUIDE.md and the Security Trade-off section.",
      "Run verify after apply, then reboot when prompted.",
    ],
  },
  rollback: {
    label: "Undo path",
    title: "Restore tracked settings from the manifest.",
    description:
      "The rollback script restores captured state first, then falls back to documented defaults where no manifest state exists.",
    command: 'cd "<path-to-repo>"\n.\\REVERT-EVERYTHING.ps1',
    steps: [
      "Run from Administrator PowerShell.",
      "Let the manifest-driven rollback finish before rebooting.",
      "Run verify again and inspect anything still marked drifted.",
    ],
  },
};

const header = document.querySelector(".site-header");
const toast = document.querySelector(".toast");
const pathTablist = document.querySelector(".path-tabs");
const pathPanel = document.getElementById("path-panel");
const pathLive = document.getElementById("path-live");
const pathTabs = Array.from(document.querySelectorAll(".path-tab"));
const filterButtons = Array.from(document.querySelectorAll(".filter-button"));
const tweakCards = Array.from(document.querySelectorAll(".tweak-card"));

const showToast = (message) => {
  toast.textContent = message;
  toast.classList.add("is-visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => {
    toast.classList.remove("is-visible");
  }, 1900);
};

const copyText = async (id) => {
  const target = document.getElementById(id);
  if (!target) {
    return;
  }

  const text = target.textContent.trim();

  try {
    await navigator.clipboard.writeText(text);
    showToast("Copied command.");
  } catch {
    const field = document.createElement("textarea");
    field.value = text;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.left = "-999px";
    document.body.append(field);
    field.select();

    const copied = document.execCommand("copy");
    field.remove();
    showToast(copied ? "Copied command." : "Copy failed. Select the command manually.");
  }
};

const renderPath = (key) => {
  const data = pathData[key];
  if (!data) {
    return;
  }

  document.getElementById("path-label").textContent = data.label;
  document.getElementById("path-title").textContent = data.title;
  document.getElementById("path-description").textContent = data.description;
  document.getElementById("path-command").textContent = data.command;

  const steps = document.getElementById("path-steps");
  steps.replaceChildren(
    ...data.steps.map((step) => {
      const item = document.createElement("li");
      item.textContent = step;
      return item;
    }),
  );

  let activeTab = null;
  pathTabs.forEach((tab) => {
    const active = tab.dataset.path === key;
    tab.classList.toggle("is-active", active);
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
    if (active) {
      activeTab = tab;
    }
  });

  if (activeTab && pathPanel) {
    pathPanel.setAttribute("aria-labelledby", activeTab.id);
  }

  if (pathLive && activeTab) {
    pathLive.textContent = `${activeTab.textContent.trim()}. ${data.title}`;
  }
};

const movePathTab = (current, key) => {
  const index = pathTabs.indexOf(current);
  if (index < 0) {
    return;
  }

  let next = index;
  if (key === "ArrowRight") {
    next = (index + 1) % pathTabs.length;
  } else if (key === "ArrowLeft") {
    next = (index - 1 + pathTabs.length) % pathTabs.length;
  } else if (key === "Home") {
    next = 0;
  } else if (key === "End") {
    next = pathTabs.length - 1;
  } else {
    return;
  }

  const nextTab = pathTabs[next];
  renderPath(nextTab.dataset.path);
  nextTab.focus();
};

const filterTweaks = (filter) => {
  tweakCards.forEach((card) => {
    const visible = filter === "all" || card.dataset.tier === filter;
    card.classList.toggle("is-hidden", !visible);
  });

  filterButtons.forEach((button) => {
    const active = button.dataset.filter === filter;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
};

if (pathTablist) {
  pathTablist.addEventListener("keydown", (event) => {
    const tab = event.target.closest("[data-path]");
    if (!tab || pathTabs.indexOf(tab) < 0) {
      return;
    }

    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft" && event.key !== "Home" && event.key !== "End") {
      return;
    }

    event.preventDefault();
    movePathTab(tab, event.key);
  });
}

document.addEventListener("click", (event) => {
  const copyButton = event.target.closest("[data-copy]");
  if (copyButton) {
    copyText(copyButton.dataset.copy);
    return;
  }

  const tab = event.target.closest("[data-path]");
  if (tab) {
    renderPath(tab.dataset.path);
    return;
  }

  const filter = event.target.closest("[data-filter]");
  if (filter) {
    filterTweaks(filter.dataset.filter);
  }
});

const syncHeader = () => {
  header.dataset.elevated = String(window.scrollY > 12);
};

window.addEventListener("scroll", syncHeader, { passive: true });
syncHeader();
