# rfd (Ruby on Files & Directories)

rfd is a terminal-based filesystem explorer, inspired by the legendary freesoft MS-DOS filer "FD", with Vim flavor.

## Installation

    % gem install rfd

## Requirements

* Ruby 2.5 or newer
* NCurses with wide character support (ncursesw) recommended for best Unicode display

### macOS: Setting up ncursesw for Unicode borders

macOS comes with an older system ncurses that doesn't fully support Unicode. For proper Unicode box-drawing characters, install and link Homebrew's ncurses before installing the curses gem:

    % brew install ncurses
    % brew link --force ncurses
    % gem install curses

## Tested environments

Mac OS X Mountain Lion and newer, Ubuntu 13.04 and newer

## Screenshot

![screenshot](https://www.evernote.com/shard/s20/sh/a0a275ee-39b5-4ba4-9374-8534f4ee2a24/377c504f45f17a75eb2ea12bd015b6ee/deep/0/rfd_screenshot.png)

## Start Me Up

Open up your terminal and type:

    % rfd

You can also pass in a starting directory name, which defaults to `.`.

    % rfd ~/src/rails


## Commands

You can send commands to rfd by pressing some chars on your keyboard, just like Vim.
If you're unfamiliar with this sort of command system, I recommend you to play with `vimtutor` before you go any further.

Press `?` to see the built-in help screen with all available commands.

All available commands in rfd are defined as Ruby methods here. https://github.com/amatsuda/rfd/tree/master/lib/rfd/commands.rb

### Changing the current directory

* `<Enter>`: cd into the directory where the cursor is on. For files, opens with viewer.
* `<Delete>` (or \<Backspace\> on your keyboard, probably?): Go up to the upper directory (cd ..).
* `-`: Get back to where you once belonged (popd).
* `@`: Open directory tree browser for navigation.
* `~`: Go to home directory.

### Moving the cursor

* `j`: Move down.
* `k`: Move up.
* `h`: Move left. At the leftmost column, move to the right end column at the previous page.
* `l`: Move right. At the rightmost column, move to the left end column at the next page.

### The {count} parameter

Some commands such as `j` or `k` take a number parameter called {count}. For passing a {count} parameter, just type in a number prior to the command.
For example, `3j` moves the cursor to 3 lines below, and `999k` will take your cursor to 999 lines above.

### Jumping the cursor

* `H`: Move to the top of the current page.
* `M`: Move to the middle of the current page.
* `L`: Move to the bottom of the current page.

### Switching the page

* `ctrl-n, ctrl-f`: Move to the top of the next page.
* `ctrl-p, ctrl-b`: Move to the top of the previous page.
* `g`: Move to the top of the first page.
* `G`: Move to the bottom of the last page.

### Finding a file / directory

You can find a file by typing the first letter of it immediately after the find commands.

* `f{char}`: Move to the next file / directory of which name starts with the given char.
* `F{char}`: Move to the previous file / directory of which name starts with the given char.
* `n`: Repeat the last `f` or `F`.
* `N`: Repeat the last `f` or `F` in reverse direction.

### Searching, sorting

For commands like these that require a parameter string, type the parameter in the command line at the bottom of the screen, and press \<Enter\>.

* `/`: Grep the current directory with the given parameter. The parameter will be interpreted as Ruby Regexp (e.g. `.*\.rb$`).
* `s`: Sort files / directories in the current directory in the given order.
    * (none): by name
    * r     : reverse order by name
    * s, S  : order by file size
    * sr, Sr: reverse order by file size
    * t     : order by mtime
    * tr    : reverse order by mtime
    * c     : order by ctime
    * cr    : reverse order by ctime
    * u     : order by atime
    * ur    : reverse order by atime
    * e     : order by extname
    * er    : reverse order by extname

### Marking files / directories

You can send a command to the file / directory on which the cursor is on. Or, you can send a command to multiple files / directories at once by marking them first.
The mark is drawn as a `*` char on the left of each file / directory name.

* `<Space>`: Mark / unmark current file / directory.
* `ctrl-a`: Mark / unmark all file / directories in the current directory.

### Manipulating files / directories

As stated above, you can send a command to one or more files / directories. In this document, the term "selected items" means "(the marked files / directories) || (the file / directory on which the cursor is on)".

* `c`: Copy selected items (cp). Opens tree browser to select destination.
* `m`: Move selected items (mv). Opens tree browser to select destination.
* `d`: Move selected items into the Trash.
* `D`: Delete selected items.
* `r`: Rename selected items. This command takes a sed-like argument separated by a `/`. For example, changing all .html files' extension to .html.erb could be done by `\.html$/.html.erb`.

### Yank and Paste

`y` & `p` works just like Windows-c & Windows-v on explorer.exe.

* `y`: Yank selected items.
* `p`: Paste yanked items into the directory on which the cursor is, or into the current directory.

### Creating files / directories

* `t`: Create a new file (touch).
* `K`: Creat a new directory (mkdir).
* `S`: Create new symlink to the current file / directory (ln -s).

### Attributes

* `a`: Change permission of selected items (chmod). Takes chmod-like argument such as `g+w`, `755`.
* `w`: Change the owner of of selected items (chown). Takes chown-like argument such as `alice`, `nobody:nobody`.

### Viewing, Editing, Opening

* `<Enter>`: Open directory, or view file. For images, shows inline preview. For audio, plays with system player.
* `v`: View current file with the system $VIEWER such as `less`.
* `e`: Edit current file with the system $EDITOR such as `vim`.
* `o`: Send the `open` command.
* `P`: Toggle preview window (shows file contents with syntax highlighting).

### Manipulating archives

* `u`: Unarchive .zip, .gz, or .tar.gz file into the current directory.
* `z`: Archive selected items into a .zip file with the given name.

### Handling .zip files

You can `cd` into a .zip file as if it's just a directory, then unarchive selected items, view files in it, and even create new files or edit files in the archive.

### Splitting columns

* `ctrl-w`: Change the window split size to the {count} value (e.g. `4<C-w>` to split the window into 4 columns). The default number of columns is 2.

### Using mouse

Mouse is available if your terminal supports it. You can move the cursor by clicking on a file / directory. Double clicking on a file / directory is equivalent to pressing \<Enter\> on it.

### Misc

* `ctrl-l`: Refresh the whole screen.
* `C`: Copy selected items' paths to the clipboard.
* `O`: Open a new terminal window at the current directory.
* `!`: Execute a shell command.
* `?`: Show help screen.
* `q`: Quit the app.

## How to manually execute a command, or how the commands are executed

By pressing `:`, you can enter the command-line mode. Any string given in the command line after `:` will be executed as Ruby method call in the `Controller` instance.
For instance, `:j` brings your cursor down, `:mkdir foo` makes a directory named "foo". And `:q!` of course works as you might expect, since `q!` method is implemented so.


## Features

### File Icons

rfd displays file type icons using Nerd Fonts. If you have a Nerd Font installed, you'll see icons for directories, symlinks, and various file types (Ruby, JavaScript, Markdown, etc.).

To disable icons:

    % RFD_NO_ICONS=1 rfd

### Preview Window

When the file list is multi-paned (default), rfd shows the preview window in an inactive pane. The preview window shows a preview of the file or directory where the cursor is on.

* **Code files**: Syntax-highlighted preview (via Rouge)
* **Directories**: List of contents
* **Archives**: Tree view of zip/tar.gz contents
* **Markdown**: Formatted with headers and lists highlighted
* **Images**: Inline preview (in supported terminals)
* **Binary files**: Indicated as `[Binary file]`

However, with this feature enabled, the cursor would not move smoothly. In that case, you can disable (toggle) the preview window by pressing `P`.

### Directory Tree Browser

Press `@` to open an interactive directory tree browser with:
* **Fuzzy filtering**: Type to filter directories
* **Tree navigation**: `j/k` or arrows to move, `Enter` to select
* **Expand/collapse**: `h/l` to collapse/expand directories
* **Quick access**: `~` for home, `/` for root
* **Bookmarks**: `@` to switch to bookmark view

### Bookmarks

Save frequently used directories for quick access:
* In tree or bookmark view, press `^B` to toggle bookmark on current directory
* Press `@` twice (or `@` then `@` in tree view) to see bookmarks
* Bookmarks are saved to `~/.config/rfd/bookmarks`


## Environment Variables

* `RFD_NO_ICONS`: Set to `1` to disable file icons (useful if you don't have a Nerd Font installed)
* `EDITOR`: Editor used for the `e` command (default: vim)
* `VIEWER`: Viewer used for the `v` command (default: less)

## Contributing

Send me your pull requests here. https://github.com/amatsuda/rfd
