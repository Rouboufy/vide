-- Hide Yazi status bar by overriding Status:render to return empty layout
function Status:render(self)
  return {}
end
