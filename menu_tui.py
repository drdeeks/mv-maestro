#!/usr/bin/env python3
"""
Unified Navigation Menu — Textual TUI
Replaces the legacy fzf/bash menu (dynamic_menu.sh:_menu_show_main) with a
robust, keyboard-driven TUI while keeping the bash functions themselves as
the single source of truth for both menu data and command execution.

Menu data (categories + items) is read directly from the MENU_* bash arrays
in modules/dynamic_menu.sh via the `_menu_dump_data` helper — nothing is
duplicated here. Commands are executed by suspending the TUI and handing the
real terminal back to bash (via App.suspend()), so interactive commands
(passphrase prompts, fzf pickers, sudo, pagers, editors) work exactly as
they always have.

Usage:
    python3 menu_tui.py
    (wired up to the `dm` / `dmenu` shell aliases — see dynamic_menu.sh)
"""

from __future__ import annotations

import os
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal
from textual.screen import ModalScreen
from textual.widgets import Button, Footer, Header, Input, Label, Static, Tree
from textual.widgets.tree import TreeNode

PROFILE_DIR = Path(os.environ.get("_MENU_TUI_PROFILE_DIR", str(Path.home() / "projects" / "MV-Maestro")))
MV_MAESTRO = PROFILE_DIR / "bash_enhanced.sh"
DOCKER_TUI = PROFILE_DIR / "docker_tui.py"
UNIT_SEP = "\x1f"


@dataclass
class MenuItem:
    category: str
    label: str
    desc: str
    cmd: str
    interactive: bool = False  # True if command is interactive (prompts, editors, etc.)
    purpose: str = ""          # Detailed purpose description
    includes: list[str] = None # List of functions/features included
    usage: str = ""            # Usage placeholder/syntax example
    
    def __post_init__(self):
        if self.includes is None:
            self.includes = []


@dataclass
class MenuCategory:
    num: str
    label: str
    items: list[MenuItem]


def load_menu_data(timeout: float = 15.0) -> tuple[list[MenuCategory], Optional[str]]:
    """Dump categories/items straight from the bash MENU_* arrays.

    Returns (categories, error). On failure, categories is [] and error is a
    human-readable message (bash_enhanced.sh missing, dump function missing,
    timeout, etc).
    """
    if not MV_MAESTRO.exists():
        return [], f"Not found: {MV_MAESTRO}"

    script = f'source "{MV_MAESTRO}" >/dev/null 2>&1; _menu_dump_data'
    try:
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return [], "Timed out loading menu data from bash_enhanced.sh"
    except OSError as exc:
        return [], f"Failed to launch bash: {exc}"

    if result.returncode != 0 and not result.stdout.strip():
        stderr = result.stderr.strip() or "unknown error"
        return [], f"_menu_dump_data failed: {stderr}"

    categories: dict[str, MenuCategory] = {}
    order: list[str] = []
    for line in result.stdout.splitlines():
        parts = line.split(UNIT_SEP)
        if not parts:
            continue
        kind = parts[0]
        if kind == "CATEGORY" and len(parts) >= 3:
            num, label = parts[1], parts[2]
            categories[num] = MenuCategory(num=num, label=label, items=[])
            order.append(num)
        elif kind == "ITEM" and len(parts) >= 9:
            num, label, desc, cmd, interactive, purpose, includes, usage = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]
            cat = categories.get(num)
            if cat is not None:
                includes_list = [i.strip() for i in includes.split(",") if i.strip()] if includes else []
                cat.items.append(MenuItem(
                    category=num, label=label, desc=desc, cmd=cmd,
                    interactive=(interactive.lower() == "y"),
                    purpose=purpose,
                    includes=includes_list,
                    usage=usage
                ))

    if not categories:
        return [], "No menu data returned — is dynamic_menu.sh up to date?"

    return [categories[n] for n in order], None


class InputDialog(ModalScreen[Optional[str]]):
    """Prompt for optional arguments before running a command."""

    DEFAULT_CSS = """
    InputDialog { align: center middle; }
    InputDialog > Container {
        width: 70; height: auto; padding: 2;
        border: thick $primary; background: $surface;
    }
    InputDialog .message { margin-bottom: 1; }
    InputDialog .hint { color: $text-muted; margin-bottom: 1; }
    InputDialog Input { width: 100%; margin-bottom: 1; }
    InputDialog .buttons { width: 100%; layout: horizontal; margin-top: 1; }
    InputDialog Button { width: 1fr; margin: 0 1; }
    """

    def __init__(self, item: MenuItem) -> None:
        self.item = item
        super().__init__()

    def compose(self) -> ComposeResult:
        with Container():
            yield Label(f"Run: {self.item.label}", classes="message")
            yield Label(f"$ {self.item.cmd} [args]", classes="hint")
            yield Input(placeholder="optional arguments — Enter to run, Esc to cancel", id="args")
            with Horizontal(classes="buttons"):
                yield Button("Cancel", variant="default", id="cancel")
                yield Button("Run", variant="primary", id="run")

    def on_mount(self) -> None:
        self.query_one("#args", Input).focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "run":
            self.dismiss(self.query_one("#args", Input).value)
        else:
            self.dismiss(None)

    def on_key(self, event) -> None:
        if event.key == "escape":
            self.dismiss(None)


class MenuTUI(App):
    """Unified navigation menu for the enhanced bash profile."""

    TITLE = "MV Maestro — A steady hand that turns chaos back into a well orchestrated symphony."

    CSS = """
    Screen { layout: vertical; }
    #body { layout: horizontal; height: 1fr; }
    #menu-tree { width: 46; border-right: solid $accent; }
    #detail { width: 1fr; padding: 1 2; }
    #status-bar {
        height: 1; dock: bottom; background: $panel; color: $text;
        padding: 0 1;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("r", "reload", "Reload menu"),
        Binding("/", "focus_filter", "Filter"),
        Binding("escape", "clear_filter", "Clear filter", show=False),
        Binding("enter", "noop", "Run", show=False),
    ]

    def __init__(self, initial_category: Optional[str] = None) -> None:
        super().__init__()
        self.categories: list[MenuCategory] = []
        self.load_error: Optional[str] = None
        self.last_status: str = "Ready."
        self.initial_category = initial_category
        self._filter_text: str = ""
        self._all_nodes: list = []  # Store all leaf nodes for filtering

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal(id="body"):
            yield Tree("Menu", id="menu-tree")
            yield Static(id="detail")
        yield Static(self.last_status, id="status-bar")
        yield Footer()

    def on_mount(self) -> None:
        self.reload_menu()

    def action_reload(self) -> None:
        """Refresh the menu data from bash."""
        self.reload_menu()

    def action_focus_filter(self) -> None:
        """Enter filter mode - focus tree and show prompt."""
        tree = self.query_one("#menu-tree", Tree)
        tree.focus()
        self.set_status("Filter: type to search... (Esc to clear)")

    def action_clear_filter(self) -> None:
        """Clear filter and show all nodes."""
        tree = self.query_one("#menu-tree", Tree)
        self._filter_text = ""
        self._show_all_nodes(tree.root)
        self.set_status("Ready.")

    def _show_all_nodes(self, node: TreeNode) -> None:
        """Recursively show all nodes."""
        node.expand()
        for child in node.children:
            self._show_all_nodes(child)

    def on_key(self, event) -> None:
        """Handle typing in filter mode."""
        tree = self.query_one("#menu-tree", Tree)
        if tree.has_focus and event.key not in ("q", "enter", "escape", "up", "down", "left", "right", "tab", "shift+tab"):
            if event.key == "backspace":
                self._filter_text = self._filter_text[:-1]
            elif len(event.key) == 1:
                self._filter_text += event.key
            self._apply_filter()
            event.prevent_default()

    def _apply_filter(self) -> None:
        """Apply filter text to tree nodes."""
        tree = self.query_one("#menu-tree", Tree)
        if self._filter_text:
            self._filter_nodes(tree.root, self._filter_text.lower())
        else:
            self._show_all_nodes(tree.root)
        self.set_status(f"Filter: {self._filter_text}")

    def _filter_nodes(self, node: TreeNode, filter_text: str) -> bool:
        """Recursively filter nodes. Returns True if node or any child matches."""
        label = str(node._label).lower()
        matches = filter_text in label
        
        # Check children
        child_matches = False
        for child in node.children:
            if self._filter_nodes(child, filter_text):
                child_matches = True
        
        # Show/hide based on matches
        if matches or child_matches:
            node.expand()
            return True
        else:
            node.collapse()
            return False

    def action_noop(self) -> None:
        pass

    def set_status(self, message: str) -> None:
        self.last_status = message
        try:
            self.query_one("#status-bar", Static).update(message)
        except Exception:
            pass

    def reload_menu(self) -> None:
        self.categories, self.load_error = load_menu_data()
        tree = self.query_one("#menu-tree", Tree)
        tree.clear()
        tree.root.expand()
        if self.load_error:
            tree.root.add_leaf(f"⚠ {self.load_error}", data=None)
            self.set_status(f"Error: {self.load_error}")
            return

        target_node: Optional[TreeNode] = None
        for cat in self.categories:
            expand = cat.num == self.initial_category
            cat_node: TreeNode = tree.root.add(cat.label, data=None, expand=expand)
            for item in cat.items:
                leaf = cat_node.add_leaf(item.label, data=item)
                if expand and target_node is None:
                    target_node = leaf

        if target_node is not None:
            # Deferred: the Tree needs a render pass before it can move its
            # cursor reliably (calling select_node synchronously here is a
            # no-op on first mount).
            self.call_after_refresh(tree.select_node, target_node)
            self.call_after_refresh(tree.scroll_to_node, target_node)

        self.set_status(f"Loaded {sum(len(c.items) for c in self.categories)} commands "
                         f"across {len(self.categories)} categories.")

    def on_tree_node_highlighted(self, event: Tree.NodeHighlighted) -> None:
        data = event.node.data
        detail = self.query_one("#detail", Static)
        if isinstance(data, MenuItem):
            interactive_marker = "[bold yellow]🔄 INTERACTIVE[/bold yellow]" if data.interactive else "[dim]One-time command[/dim]"
            purpose_line = f"[bold]Purpose:[/bold] {data.purpose}" if data.purpose else ""
            includes_lines = "\n".join(f"  • {inc}" for inc in data.includes) if data.includes else ""
            usage_line = f"[bold cyan]Usage:[/bold cyan] {data.usage}" if data.usage else ""
            
            detail.update(
                f"[b]{data.label}[/b]\n\n"
                f"[bold cyan]$ {data.cmd}[/bold cyan]\n\n"
                f"{interactive_marker}\n\n"
                f"{purpose_line}\n\n"
                f"{usage_line}\n\n"
                f"[dim]Includes:[/dim]\n{includes_lines}\n\n"
                f"[dim]Press Enter to run — you'll be prompted for optional "
                f"arguments, then the terminal is handed to the command "
                f"directly (sudo/passphrase/fzf prompts all work normally).[/dim]"
            )
        else:
            detail.update("[dim]Select a command from the menu on the left.[/dim]")

    def on_tree_node_selected(self, event: Tree.NodeSelected) -> None:
        data = event.node.data
        if isinstance(data, MenuItem):
            self.run_menu_item(data)

    def run_menu_item(self, item: MenuItem) -> None:
        # Special-case: launch the existing Docker TUI directly rather than
        # duplicating its logic.
        if item.cmd == "docker-tui" and DOCKER_TUI.exists():
            self.launch_external(f"python3 {shlex.quote(str(DOCKER_TUI))}", label=item.label)
            return
        self.prompt_and_run(item)

    def prompt_and_run(self, item: MenuItem) -> None:
        def after_prompt(args: Optional[str]) -> None:
            if args is None:
                self.set_status("Cancelled.")
                return
            cmd_line = item.cmd if not args.strip() else f"{item.cmd} {args.strip()}"
            shell_cmd = (
                f'clear; printf "\\033[1;36m\\$ %s\\033[0m\\n\\n" {shlex.quote(cmd_line)}; '
                f'source {shlex.quote(str(MV_MAESTRO))} >/dev/null 2>&1; '
                f'{cmd_line}; '
                f'ec=$?; echo; '
                f'if [ $ec -eq 0 ]; then printf "\\033[0;32m\\xe2\\x9c\\x93 exited 0\\033[0m\\n"; '
                f'else printf "\\033[0;31m\\xe2\\x9c\\x97 exited %s\\033[0m\\n" "$ec"; fi; '
                f'read -rp "Press Enter to return to menu..." _'
            )
            self.launch_external(f"bash -c {shlex.quote(shell_cmd)}", label=item.label)

        self.push_screen(InputDialog(item), after_prompt)

    def launch_external(self, shell_command: str, label: str) -> None:
        self.set_status(f"Running: {label} ...")
        try:
            with self.suspend():
                os.system(shell_command)
        except Exception as exc:  # SuspendNotSupported, etc.
            self.set_status(f"Could not suspend TUI to run '{label}': {exc}")
            return
        self.set_status(f"Finished: {label}")


def main() -> None:
    import sys

    initial_category = None
    if len(sys.argv) > 1 and sys.argv[1] in {"1", "2", "3", "4", "5", "6", "7", "8", "9"}:
        initial_category = sys.argv[1]
    MenuTUI(initial_category=initial_category).run()


if __name__ == "__main__":
    main()
