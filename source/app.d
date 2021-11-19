import vibe.vibe;
import std.algorithm;
import hunt.xml;

private ushort port = 8080;
private NativePath gitPath;

private struct Icon
{
  string name;
  string[] tags;
  string[][string] versions;
  string color;
  string[string][] aliases;
}

private Icon[string] icons;

void main()
{
  auto listener = listenHTTP(getSettings(), getRouter());
  scope (exit)
  {
    listener.stopListening();
  }

  icons = getIcons();

  runApplication();
}

private Icon[string] getIcons()
{
  Icon[string] iconMap;
  Icon[] iconArr = deserializeJson!(Icon[])(
      parseJsonString(readFileUTF8(gitPath ~ NativePath.Segment("devicon.json"))));
  foreach (Icon icon; iconArr)
  {
    iconMap[icon.name] = icon;
  }
  return iconMap;
}

private HTTPServerSettings getSettings()
{
  auto settings = new HTTPServerSettings;
  readOption("p|port", &port, "Port to bind to (Default: 8080)");
  string gitPathString = "./devicon-git";
  readOption("devicon-git", &gitPathString,
      "Location of the devicon git repository (Default: './devicon-git')");
  gitPath = NativePath.fromString(gitPathString);
  settings.port = port;
  settings.bindAddresses = ["127.0.0.1"];
  return settings;
}

private URLRouter getRouter()
{
  auto router = new URLRouter;
  router.get("/", &helloPage);
  router.get("/:icon/:version", &iconPage);
  return router;
}

private void helloPage(HTTPServerRequest req, HTTPServerResponse res)
{
  res.contentType = "text/html";
  res.writeBody(format(`<p>Welcome to the devicon CDN serving <code>devicon@%s</code>!</p>
<p><b>Usage:</b> <code>/&lt;icon name>/&lt;icon version></code></p>
<p><b>Arguments:</b></p>
<ul>
  <li><code>color</code> - Fill color of the icon <i>(Optional, only works for <code>plain</code> icons)</i></li>
  <li>
    <code>size</code> - Size of the icon,
    sets the <code>width</code> and <code>height</code> attributes of the svg <i>(Optional)</i>
  </li>
</ul>
<p>
  <b>Example:</b>
  <code>
    <a href="/devicon/plain?color=gray&size=50px">
      /devicon/plain?color=gray&size=50px</a>
  </code>
</p>`,
      getDeviconVersion()));
}

private void iconPage(HTTPServerRequest req, HTTPServerResponse res)
{
  string iconName = req.params["icon"];
  string versionName = req.params["version"];
  if (!(iconName in icons))
  {
    return;
  }
  Icon icon = icons[iconName];
  if (!(icon.versions["svg"].canFind(versionName)))
  {
    if (versionName == "plain" && icon.versions["svg"].canFind("original"))
      versionName = "original";
    else if (versionName == "plain-wordmark" && icon.versions["svg"].canFind("original-wordmark"))
      versionName = "original-wordmark";
    else
      return;
  }
  string svg = readFileUTF8(gitPath ~ NativePath.fromString(
      format("./icons/%1$s/%1$s-%2$s.svg", iconName, versionName)));
  auto color = req.query.get("color");
  auto size = req.query.get("size");
  if (color && startsWith(req.params["version"], "plain"))
    svg = getColoredIcon(svg, color);
  if (size)
    svg = getSizedIcon(svg, size);
  res.contentType = "image/svg+xml";
  res.writeBody(svg);
}

private void walkXmlNodes(Document doc, void delegate(Element) callback)
{
  Element[] nodeQueue = [];
  nodeQueue ~= doc.firstNode();
  while (nodeQueue.length > 0)
  {
    if (nodeQueue[0]!is null)
    {
      callback(nodeQueue[0]);
      nodeQueue ~= nodeQueue[0].firstNode();
      nodeQueue ~= nodeQueue[0].nextSibling();
    }
    nodeQueue = nodeQueue[1 .. $];
  }
}

private string getColoredIcon(string svg, string color)
{
  Document doc = Document.parse(svg);
  if (!doc.validate())
  {
    throw new Exception("Invalid SVG");
  }
  walkXmlNodes(doc, (node) {
    switch (node.getName())
    {
    case "svg":
      // Add "fill" attribute to the root svg element
      node.appendAttribute(new Attribute("fill", color));
      break;
    default:
      // Remove "fill" attribute from all other elements

      // Removes all attributes from the node first and then adds
      // every attribute back again, execpt "fill",
      // because currentNode.removeAttribute() seems
      // to be broken in the library
      Attribute[] attributes = [];
      Attribute currentAttribute = node.firstAttribute();
      while (currentAttribute !is null)
      {
        if (currentAttribute.localName() != "fill")
          attributes ~= currentAttribute;
        currentAttribute = currentAttribute.nextAttribute();
      }
      node.removeAllAttributes();
      foreach (Attribute attribute; attributes)
      {
        node.appendAttribute(attribute);
      }
      break;
    }
  });
  return doc.toString();
}

private string getSizedIcon(string svg, string size)
{
  Document doc = Document.parse(svg);
  if (!doc.validate())
  {
    throw new Exception("Invalid SVG");
  }
  walkXmlNodes(doc, (node) {
    if (node.getName() == "svg")
    {
      node.appendAttribute(new Attribute("width", size));
      node.appendAttribute(new Attribute("height", size));
    }
  });
  return doc.toString();
}

private string getDeviconVersion()
{
  return parseJsonString(readFileUTF8(gitPath ~ NativePath.Segment("package.json")))["version"]
    .get!string;
}
