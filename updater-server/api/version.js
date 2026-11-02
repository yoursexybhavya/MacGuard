module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Content-Type", "application/json");

  const repo = "yoursexybhavya/MacGuard";
  const defaultVersion = "1.0.1";
  const defaultNotes = "MacGuard 1.0.1: Standalone offline AI engine (0 MB idle RAM, no Ollama required), one-click Finder inspection, and auto-update support.";
  const defaultDownloadUrl = `https://github.com/${repo}/releases/download/v${defaultVersion}/MacGuard.zip`;

  try {
    const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: {
        "User-Agent": "MacGuard-Updater/1.0"
      }
    });

    if (response.ok) {
      const data = await response.json();
      const tagName = data.tag_name || `v${defaultVersion}`;
      const version = tagName.replace(/^v/, "");
      
      const zipAsset = (data.assets || []).find(a => a.name.endsWith(".zip"));
      const downloadUrl = zipAsset ? zipAsset.browser_download_url : `https://github.com/${repo}/releases/download/${tagName}/MacGuard.zip`;

      return res.status(200).json({
        name: "MacGuard",
        version: version,
        tagName: tagName,
        releaseNotes: data.body || defaultNotes,
        downloadUrl: downloadUrl,
        publishedAt: data.published_at || new Date().toISOString(),
        minimumMacOS: "14.0",
        appleSiliconOnly: true
      });
    }
  } catch (err) {
    console.error("GitHub API fetch error:", err);
  }

  // Fallback response
  return res.status(200).json({
    name: "MacGuard",
    version: defaultVersion,
    tagName: `v${defaultVersion}`,
    releaseNotes: defaultNotes,
    downloadUrl: defaultDownloadUrl,
    publishedAt: new Date().toISOString(),
    minimumMacOS: "14.0",
    appleSiliconOnly: true
  });
};
