local configs = require 'lspconfig.configs'

local M = {
  util = require 'lspconfig.util',
}

function M.available_servers()
  vim.deprecate('lspconfig.available_servers', 'lspconfig.util.available_servers', '0.1.4', 'lspconfig')
  return M.util.available_servers()
end

M.util.get_workspace = function(config, bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buf_path = vim.fs.dirname(bufname)
  local root_dir = vim.fs.dirname(vim.fs.find(config.workspace_markers, { path = buf_path, upward = true })[1])
  local ws = {
    name = root_dir,
    uri = vim.uri_from_fname(root_dir),
  }
  return ws
end

M.util.should_reuse_client = function(client, config)
  -- TODO: should use add_workspace_folder once it's client aware
  local bufnr = vim.api.nvim_get_current_buf()
  local ws = M.util.get_workspace(config, bufnr)
  if not ws then
    return
  end
  local found
  for _, folder in ipairs(client.workspace_folders) do
    if folder.uri == ws.uri then
      found = true
    end
  end
  if found and client.name == config.name then
    return true
  end
end

---Setup a language server by providing a name
---@param server_name string name of the language server
---@param overrrides table? when available it will take predence over any default configurations
function M.setup(server_name, overrrides)
  vim.validate { name = { server_name, 'string' } }
  overrrides = overrrides or {}
  local success, conf = pcall(require, 'lspconfig.server_configurations.' .. server_name)
  if not success or not conf.default_config.workspace_markers then
    vim.notify(
      string.format('[lspconfig] This setup API is not supported for (%s) ..', server_name),
      vim.log.levels.WARN
    )
    return
  end
  local config = vim.tbl_deep_extend('force', conf.default_config, overrrides)

  -- this is missing by default for some reason..
  config.name = config.name or server_name

  local lsp_group = vim.api.nvim_create_augroup('lspconfig', { clear = false })
  local bufnr = vim.api.nvim_get_current_buf()
  config.workspace_folders = config.workspace_folders or { M.util.get_workspace(config, bufnr) }
  local opts = {
    reuse_client = M.util.should_reuse_client,
  }
  vim.lsp.start(config, opts)
  vim.api.nvim_create_autocmd('FileType', {
    pattern = table.concat(config.filetypes, ','),
    callback = function()
      vim.lsp.start(config, opts)
    end,
    group = lsp_group,
    desc = string.format('Call vim.lsp.start automatically for %s', config.name),
  })
end

local mt = {}
function mt:__index(k)
  if configs[k] == nil then
    local success, config = pcall(require, 'lspconfig.server_configurations.' .. k)
    if success then
      configs[k] = config
    else
      vim.notify(
        string.format(
          '[lspconfig] Cannot access configuration for %s. Ensure this server is listed in '
          .. '`server_configurations.md` or added as a custom server.',
          k
        ),
        vim.log.levels.WARN
      )
      -- Return a dummy function for compatibility with user configs
      return { setup = function() end }
    end
  end
  return configs[k]
end

return setmetatable(M, mt)
