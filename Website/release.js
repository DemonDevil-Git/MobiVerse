const RELEASE_API = "https://api.github.com/repos/DemonDevil-Git/MobiVerse/releases/latest";
const INSTALLER_EXTENSIONS = [
  ".dmg",
  ".pkg",
  ".exe",
  ".msi",
  ".msix",
  ".appx",
  ".appxbundle",
  ".msixbundle",
];

const isInstallerAsset = (asset) => {
  const name = asset.name?.toLowerCase();
  return Boolean(name && INSTALLER_EXTENSIONS.some((extension) => name.endsWith(extension)));
};

const formatBytes = (bytes) => {
  if (!Number.isFinite(bytes) || bytes <= 0) return "";
  const units = ["B", "KB", "MB", "GB"];
  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** exponent).toFixed(exponent > 1 ? 1 : 0)} ${units[exponent]}`;
};

fetch(RELEASE_API, { headers: { Accept: "application/vnd.github+json" } })
  .then((response) => {
    if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
    return response.json();
  })
  .then((release) => {
    const assets = Array.isArray(release.assets) ? release.assets : [];
    const installerAssets = assets.filter(isInstallerAsset);
    const macAsset = installerAssets.find((asset) => asset.name?.toLowerCase().endsWith(".dmg"));
    const version = release.tag_name || release.name;
    const published = release.published_at?.slice(0, 10);

    document.querySelectorAll("[data-release-version]").forEach((element) => {
      if (version) element.textContent = version;
    });
    document.querySelectorAll("[data-release-date]").forEach((element) => {
      if (published) element.textContent = published;
    });
    document.querySelectorAll("[data-release-page]").forEach((element) => {
      if (release.html_url) element.href = release.html_url;
    });
    document.querySelectorAll("[data-macos-download]").forEach((element) => {
      if (macAsset?.browser_download_url) element.href = macAsset.browser_download_url;
    });

    const assetList = document.querySelector("[data-release-assets]");
    if (!assetList || installerAssets.length === 0) return;
    assetList.replaceChildren(
      ...installerAssets.map((asset) => {
        const item = document.createElement("li");
        const label = document.createElement("span");
        const link = document.createElement("a");
        label.textContent = `${asset.name}${asset.size ? ` · ${formatBytes(asset.size)}` : ""}`;
        link.href = asset.browser_download_url;
        link.textContent = "下载";
        item.append(label, link);
        return item;
      }),
    );
  })
  .catch(() => {
    // The verified v2.4.1 fallback remains usable when GitHub is unavailable.
  });
