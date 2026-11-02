module.exports = async (req, res) => {
  const repo = "yoursexybhavya/MacGuard";
  try {
    const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { "User-Agent": "MacGuard-Updater/1.0" }
    });
    if (response.ok) {
      const data = await response.json();
      const zipAsset = (data.assets || []).find(a => a.name.endsWith(".zip"));
      if (zipAsset && zipAsset.browser_download_url) {
        return res.redirect(302, zipAsset.browser_download_url);
      }
      if (data.tag_name) {
        return res.redirect(302, `https://github.com/${repo}/releases/download/${data.tag_name}/MacGuard.zip`);
      }
    }
  } catch (err) {
    console.error("Redirect error:", err);
  }
  return res.redirect(302, `https://github.com/${repo}/releases/latest`);
};
