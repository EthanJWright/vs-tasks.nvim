# VS Tasks

Telescope plugin to load and run tasks in a project that conform to VS Code's [Editor Tasks](https://code.visualstudio.com/docs/editor/tasks)

## Features

- ⚙ Run commands in a terminal!
  - split or float the terminal
  - source from ./vscode/tasks.json
  - source from package.json scripts
- 👀 Run any task as a watched job
- 🧵 Run any task in the background as a job
- 📖 Browse history of completed background jobs
- ✏️ edit input variables that will be used for the session
- Use VS Code's [variables](https://code.visualstudio.com/docs/editor/variables-reference) in the command (limited support, see desired features)
- Use VS Code's [launch.json](https://code.visualstudio.com/docs/editor/debugging#_launch-configurations) pattern (limited support)
- ⟳ Run tasks from your history, sorted by most used

## Example

Short Demo

![Short Demo](https://i.imgur.com/sQtRQdO.gif)

## Setup

With Plug:

```vim
Plug 'nvim-lua/popup.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim' " make sure you have telescope installed
Plug 'EthanJWright/vs-tasks.nvim'
```

With Packer:

```vim
use {
  'EthanJWright/vs-tasks.nvim',
  requires = {
    'nvim-lua/popup.nvim',
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim'
  }
}
```

With Lazy:

```lua
{
  "EthanJWright/vs-tasks.nvim",
  dependencies = {
    "nvim-lua/popup.nvim",
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
}
```

Set up keybindings:

```vim
nnoremap <Leader>ta :lua require("telescope").extensions.vstask.tasks()<CR>
nnoremap <Leader>ti :lua require("telescope").extensions.vstask.inputs()<CR>
nnoremap <Leader>th :lua require("telescope").extensions.vstask.history()<CR>
nnoremap <Leader>tl :lua require('telescope').extensions.vstask.launch()<cr>
nnoremap <Leader>tj :lua require("telescope").extensions.vstask.jobs()<CR>
nnoremap <Leader>t; :lua require("telescope").extensions.vstask.jobhistory()<CR>
```

## Usage

### When the task telescope is open

- Enter will open in toggleterm
- Ctrl-v will open in a vertical split terminal
- Ctrl-p will open in a split terminal
- Ctrl-b will run the task as a job in the background
- Ctrl-w will run the task as as a job in the background, and watch the file

### When the jobs telescope is open

- Enter will open any output in a temporary buffer
- Ctrl-w will toggle the watch status
- Ctrl-d will kill the job (j and k reserved for navigation)

### Autodetect

VS Tasks can auto detect certain scripts from your package, such as npm
scripts.

## Configuration

- Configure toggle term use
- Configure terminal behavior
- Cache json conf sets whether the config will be ran every time. If the cache
  is removed, this will also remove cache features such as remembering last
  ran command

```lua
lua <<EOF
require("vstask").setup({
  cache_json_conf = true, -- don't read the json conf every time a task is ran
  cache_strategy = "last", -- can be "most" or "last" (most used / last used)
  config_dir = ".vscode", -- directory to look for tasks.json and launch.json
  telescope_keys = { -- change the telescope bindings used to launch tasks
    vertical = '<C-v>',
    split = '<C-p>',
    tab = '<C-t>',
    current = '<CR>',
    background = '<C-b>',
    watch_job = '<C-w>',
    kill_job = '<C-d>',
  },
  autodetect = { -- auto load scripts
    npm = "on"
  },
  terminal = 'toggleterm',
  term_opts = {
    vertical = {
      direction = "vertical",
      size = "80"
    },
    horizontal = {
      direction = "horizontal",
      size = "10"
    },
    current = {
      direction = "float",
    },
    tab = {
      direction = 'tab',
    }
  },
  json_parser = vim.json.decode
})
EOF
```

### Work with json5 files

VS Code uses json5 which allows use of comments and trailing commas.
If you want to use the same tasks as your teammates, and they leave trailing commas and comments in the project's task.json,
you will need another parser than the default `vim.fn.json_decode`.

A proposed solution:
Add the following to your dependencies.

```lua
lua <<EOF
    {
      'Joakker/lua-json5',
      run = './install.sh'
    }
EOF
```

And add the following option in the setup:

```lua
lua <<EOF
require("vstask").setup({
    json_parser = require('json5').parse
})
EOF
```

## Example

### Tasks.json

In your project root set up `.vscode/tasks.json` (default config directory set to `.vscode`, but can be changed in setup)

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "🧪 Run unit tests that match the expression",
      "type": "shell",
      "command": "pytest -k '${input:expression}'"
    },
    {
      "label": "🐮 Cowsay",
      "type": "shell",
      "command": "echo ${input:cowmsg} | cowsay"
    }
  ],
  "inputs": [
    {
      "id": "expression",
      "description": "Expression to filter tests with",
      "default": "",
      "type": "promptString"
    },
    {
      "id": "cowmsg",
      "description": "Message for cow to say",
      "default": "Hello there!",
      "type": "promptString"
    }
  ]
}
```

### Functions

```lua
lua require("telescope").extensions.vstask.tasks() -- open task list in telescope
lua require("telescope").extensions.vstask.inputs() -- open the input list, set new input
lua require("telescope").extensions.vstask.history() -- search history of tasks
lua require("telescope").extensions.vstask.close() -- close the task runner (if toggleterm)
lua require("telescope").extensions.vstask.jobs() -- view and manage background tasks (Enter to kill)
```

You can also configure themes and pass options to the picker

```lua
lua require("telescope").extensions.vstask.tasks(require('telescope.themes').get_dropdown()) -- open task list in telescope
```

You can also grab the last run task and do what you want with it, such as open
it in a new terminal:

```lua
function _RUN_LAST_TASK()
  local vstask_ok, vstask = pcall(require, "vstask")
  if not vstask_ok then
    return
  end
  local cmd = vstask.get_last()
  vim.cmd("vsplit")
  vim.cmd("term " .. cmd)
end
```

## Features to implement

### Full VS Code variable support

All [variables available in VS Code](https://code.visualstudio.com/docs/editor/variables-reference) should also work in this plugin, though they are not all tested.

### Extend support for VS Code schema

At this point only the features I need professionally have been implemented.
The implemented schema elements are as follows:

- [x] Tasks: Label
- [x] Tasks: Command
- [x] Tasks: ID
- [x] Inputs: Description
- [x] Inputs: Default

As I do not use VS Code, the current implementation are the elements that seem
most immediately useful. In the future it may be good to look into implementing
other schema elements such as problemMatcher and group.
