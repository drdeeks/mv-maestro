#!/usr/bin/env python3
"""
Docker TUI - A comprehensive terminal user interface for Docker management
Similar to lazydocker but built with Textual for more features and better extensibility.

Features:
- Container management (list, start, stop, restart, logs, shell, inspect)
- Image management (list, pull, build, remove, prune)
- Volume management (list, create, remove, inspect, prune)
- Network management (list, create, remove, inspect, prune)
- Docker Compose support (up, down, logs, ps, build, restart)
- Real-time resource monitoring (CPU, memory, network, disk I/O)
- Search/filter across all resources
- Multi-worker for concurrent operations
- Keyboard-driven with vim-like bindings
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Optional
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import (
    Container, Horizontal, Vertical, Grid, ScrollableContainer
)
from textual.coordinate import Coordinate
from textual.events import Key, Mount, Resize
from textual.message import Message
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.worker import Worker, WorkerState
from textual.widgets import (
    Header, Footer, Button, Input, Label, Static, 
    DataTable, Tree, Log, ProgressBar, Sparkline, 
    Select, TabbedContent, TabPane, RichLog, Tabs
)
from textual.containers import Center, Middle
from textual import on, work
from rich.text import Text
from rich.panel import Panel
from rich.table import Table
from rich.syntax import Syntax

# Try to import docker
try:
    import docker
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False
    docker = None

# ──────────────────────────────────────────────────────────────────────────────
# DATA MODELS
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class ContainerInfo:
    id: str
    name: str
    image: str
    status: str
    state: str
    ports: str = ""
    created: str = ""
    cpu_percent: float = 0.0
    mem_percent: float = 0.0
    mem_usage: str = ""
    mem_limit: str = ""
    net_io: str = ""
    block_io: str = ""
    pids: int = 0

@dataclass
class ImageInfo:
    id: str
    repository: str
    tag: str
    size: str
    created: str
    digest: str = ""

@dataclass
class VolumeInfo:
    name: str
    driver: str
    mountpoint: str
    created: str = ""
    scope: str = "local"

@dataclass
class NetworkInfo:
    id: str
    name: str
    driver: str
    scope: str
    created: str = ""

@dataclass
class ComposeService:
    name: str
    status: str
    image: str
    ports: str = ""

# ──────────────────────────────────────────────────────────────────────────────
# CUSTOM MESSAGES
# ──────────────────────────────────────────────────────────────────────────────

class DockerDataRefresh(Message):
    """Request to refresh Docker data."""
    def __init__(self, resource_type: str = "all") -> None:
        self.resource_type = resource_type
        super().__init__()

class ShowContainerLogs(Message):
    """Show logs for a container."""
    def __init__(self, container_id: str, container_name: str) -> None:
        self.container_id = container_id
        self.container_name = container_name
        super().__init__()

class ShowContainerShell(Message):
    """Open shell in container."""
    def __init__(self, container_id: str, container_name: str) -> None:
        self.container_id = container_id
        self.container_name = container_name
        super().__init__()

class StatusMessage(Message):
    """Status bar message."""
    def __init__(self, message: str, severity: str = "information") -> None:
        self.message = message
        self.severity = severity
        super().__init__()

# ──────────────────────────────────────────────────────────────────────────────
# CUSTOM WIDGETS
# ──────────────────────────────────────────────────────────────────────────────

class MetricCard(Static):
    """A card showing a metric with label and value."""
    
    DEFAULT_CSS = """
    MetricCard {
        border: solid $primary;
        padding: 1;
        margin: 0 1;
        background: $surface;
        min-width: 20;
    }
    MetricCard .label {
        color: $text-muted;
        text-style: bold;
        margin-bottom: 1;
    }
    MetricCard .value {
        color: $accent;
        text-style: bold;
        font-size: 2;
    }
    MetricCard .unit {
        color: $text-muted;
        margin-left: 1;
    }
    """
    
    def __init__(self, label: str, value: str = "", unit: str = "") -> None:
        self.label = label
        self.value = value
        self.unit = unit
        super().__init__()
    
    def compose(self) -> ComposeResult:
        yield Label(self.label, classes="label")
        yield Label(f"{self.value} {self.unit}", classes="value")
    
    def update_value(self, value: str) -> None:
        self.value = value
        self.query_one(".value", Label).update(f"{value} {self.unit}")

class ResourceSparkline(Sparkline):
    """Sparkline for resource monitoring."""
    
    DEFAULT_CSS = """
    ResourceSparkline {
        height: 5;
        margin: 1 0;
    }
    """
    
    def __init__(self, data: list[float] = None, color: str = "$accent") -> None:
        self.data = data or [0.0] * 60
        self.color = color
        super().__init__(self.data, summary_function=max)
    
    def add_point(self, value: float) -> None:
        self.data.append(value)
        if len(self.data) > 60:
            self.data.pop(0)
        self.data = self.data  # Triggers refresh

class StatusBadge(Label):
    """Colored status badge."""
    
    DEFAULT_CSS = """
    StatusBadge {
        padding: 0 1;
        text-style: bold;
        min-width: 10;
        content-align: center middle;
    }
    StatusBadge.running { background: $success; color: $text; }
    StatusBadge.exited { background: $error; color: $text; }
    StatusBadge.paused { background: $warning; color: $text; }
    StatusBadge.created { background: $primary; color: $text; }
    StatusBadge.restarting { background: $warning; color: $text; }
    StatusBadge.unknown { background: $surface; color: $text-muted; }
    """
    
    def __init__(self, status: str) -> None:
        super().__init__(status)
        self.add_class(status.lower())

class FilterInput(Input):
    """Filter input with clear button."""
    
    DEFAULT_CSS = """
    FilterInput {
        width: 100%;
    }
    """
    
    def __init__(self, placeholder: str = "Filter...", **kwargs) -> None:
        super().__init__(placeholder=placeholder, **kwargs)
    
    def on_key(self, event: Key) -> None:
        if event.key == "escape":
            self.value = ""
            self.blur()

# ──────────────────────────────────────────────────────────────────────────────
# MODAL SCREENS
# ──────────────────────────────────────────────────────────────────────────────

class ConfirmDialog(ModalScreen[bool]):
    """Confirmation dialog."""
    
    DEFAULT_CSS = """
    ConfirmDialog {
        align: center middle;
    }
    ConfirmDialog > Container {
        width: 60;
        height: auto;
        padding: 2;
        border: thick $primary;
        background: $surface;
    }
    ConfirmDialog .message {
        margin-bottom: 2;
        text-align: center;
    }
    ConfirmDialog .buttons {
        width: 100%;
        layout: horizontal;
        margin-top: 1;
    }
    ConfirmDialog Button {
        width: 1fr;
        margin: 0 1;
    }
    """
    
    def __init__(self, message: str, title: str = "Confirm") -> None:
        self.message = message
        self.title = title
        super().__init__()
    
    def compose(self) -> ComposeResult:
        with Container():
            yield Label(self.title, classes="title")
            yield Label(self.message, classes="message")
            with Horizontal(classes="buttons"):
                yield Button("Cancel", variant="default", id="cancel")
                yield Button("Confirm", variant="error", id="confirm")
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "confirm":
            self.dismiss(True)
        else:
            self.dismiss(False)

class InputDialog(ModalScreen[str]):
    """Input dialog."""
    
    DEFAULT_CSS = """
    InputDialog {
        align: center middle;
    }
    InputDialog > Container {
        width: 60;
        height: auto;
        padding: 2;
        border: thick $primary;
        background: $surface;
    }
    InputDialog .message {
        margin-bottom: 2;
    }
    InputDialog Input {
        width: 100%;
        margin-bottom: 1;
    }
    InputDialog .buttons {
        width: 100%;
        layout: horizontal;
        margin-top: 1;
    }
    InputDialog Button {
        width: 1fr;
        margin: 0 1;
    }
    """
    
    def __init__(self, message: str, placeholder: str = "", default: str = "") -> None:
        self.message = message
        self.placeholder = placeholder
        self.default = default
        super().__init__()
    
    def compose(self) -> ComposeResult:
        with Container():
            yield Label(self.message, classes="message")
            yield Input(placeholder=self.placeholder, value=self.default, id="input")
            with Horizontal(classes="buttons"):
                yield Button("Cancel", variant="default", id="cancel")
                yield Button("OK", variant="primary", id="ok")
    
    def on_mount(self) -> None:
        self.query_one("#input", Input).focus()
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "ok":
            self.dismiss(self.query_one("#input", Input).value)
        else:
            self.dismiss(None)

class LogsScreen(ModalScreen):
    """Container logs viewer."""
    
    DEFAULT_CSS = """
    LogsScreen {
        align: center middle;
    }
    LogsScreen > Container {
        width: 90%;
        height: 90%;
        border: thick $primary;
        background: $surface;
    }
    LogsScreen .header {
        height: 3;
        background: $primary;
        padding: 0 1;
        layout: horizontal;
    }
    LogsScreen .title {
        color: $text;
        text-style: bold;
    }
    LogsScreen .controls {
        width: 1fr;
        content-align: right middle;
    }
    LogsScreen RichLog {
        height: 1fr;
        border: solid $primary;
        margin: 1;
        background: $background;
    }
    """
    
    def __init__(self, container_id: str, container_name: str) -> None:
        self.container_id = container_id
        self.container_name = container_name
        super().__init__()
    
    def compose(self) -> ComposeResult:
        with Container():
            with Horizontal(classes="header"):
                yield Label(f"📋 Logs: {self.container_name}", classes="title")
                with Horizontal(classes="controls"):
                    yield Button("Follow", variant="primary", id="follow")
                    yield Button("Clear", id="clear")
                    yield Button("Close", variant="error", id="close")
            yield RichLog(id="logs", auto_scroll=True, wrap=True, markup=True)
    
    def on_mount(self) -> None:
        self.follow_mode = True
        self.load_logs()
    
    @work
    async def load_logs(self) -> None:
        logs = self.query_one("#logs", RichLog)
        if not DOCKER_AVAILABLE:
            logs.write("[red]Docker not available[/red]")
            return
        
        try:
            client = docker.from_env()
            container = client.containers.get(self.container_id)
            
            # Get initial logs
            log_lines = container.logs(tail=200, timestamps=True).decode('utf-8', errors='replace')
            for line in log_lines.strip().split('\n'):
                logs.write(line)
            
            # Follow mode
            if self.follow_mode:
                for line in container.logs(stream=True, follow=True, timestamps=True):
                    if not self.follow_mode:
                        break
                    decoded = line.decode('utf-8', errors='replace').strip()
                    if decoded:
                        self.call_from_thread(logs.write, decoded)
        except Exception as e:
            logs.write(f"[red]Error loading logs: {e}[/red]")
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "close":
            self.follow_mode = False
            self.dismiss()
        elif event.button.id == "clear":
            self.query_one("#logs", RichLog).clear()
        elif event.button.id == "follow":
            self.follow_mode = not self.follow_mode
            event.button.label = "Following..." if self.follow_mode else "Follow"
            if self.follow_mode:
                self.load_logs()

class InspectScreen(ModalScreen):
    """JSON inspect viewer."""
    
    DEFAULT_CSS = """
    InspectScreen {
        align: center middle;
    }
    InspectScreen > Container {
        width: 90%;
        height: 90%;
        border: thick $primary;
        background: $surface;
    }
    InspectScreen .header {
        height: 3;
        background: $primary;
        padding: 0 1;
        layout: horizontal;
    }
    InspectScreen .title {
        color: $text;
        text-style: bold;
    }
    InspectScreen .controls {
        width: 1fr;
        content-align: right middle;
    }
    InspectScreen RichLog {
        height: 1fr;
        border: solid $primary;
        margin: 1;
        background: $background;
    }
    """
    
    def __init__(self, title: str, data: dict) -> None:
        self.data = data
        self.title_text = title
        super().__init__()
    
    def compose(self) -> ComposeResult:
        with Container():
            with Horizontal(classes="header"):
                yield Label(self.title_text, classes="title")
                with Horizontal(classes="controls"):
                    yield Button("Copy JSON", id="copy")
                    yield Button("Close", variant="error", id="close")
            yield RichLog(id="json", wrap=True, markup=True)
    
    def on_mount(self) -> None:
        logs = self.query_one("#json", RichLog)
        json_str = json.dumps(self.data, indent=2)
        syntax = Syntax(json_str, "json", theme="monokai", line_numbers=True)
        logs.write(syntax)
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "close":
            self.dismiss()
        elif event.button.id == "copy":
            self.app.copy_text(json.dumps(self.data, indent=2))
            self.app.notify("JSON copied to clipboard")

class BuildImageScreen(ModalScreen):
    """Docker image build screen."""
    
    DEFAULT_CSS = """
    BuildImageScreen {
        align: center middle;
    }
    BuildImageScreen > Container {
        width: 80;
        height: auto;
        max-height: 80%;
        border: thick $primary;
        background: $surface;
        padding: 1;
    }
    BuildImageScreen .field {
        margin-bottom: 1;
    }
    BuildImageScreen Label {
        text-style: bold;
        margin-bottom: 1;
    }
    BuildImageScreen Input, BuildImageScreen Select {
        width: 100%;
    }
    BuildImageScreen .buttons {
        width: 100%;
        layout: horizontal;
        margin-top: 1;
    }
    BuildImageScreen Button {
        width: 1fr;
        margin: 0 1;
    }
    BuildImageScreen #output {
        height: 20;
        border: solid $primary;
        margin-top: 1;
        background: $background;
    }
    """
    
    def compose(self) -> ComposeResult:
        with Container():
            yield Label("🔨 Build Docker Image", classes="title")
            
            with Vertical(classes="field"):
                yield Label("Dockerfile Path:")
                yield Input(placeholder="Dockerfile", value="Dockerfile", id="dockerfile")
            
            with Vertical(classes="field"):
                yield Label("Build Context:")
                yield Input(placeholder=".", value=".", id="context")
            
            with Vertical(classes="field"):
                yield Label("Image Tag:")
                yield Input(placeholder="myimage:latest", value="", id="tag")
            
            with Vertical(classes="field"):
                yield Label("Platform:")
                yield Select(
                    options=[("linux/amd64", "linux/amd64"), ("linux/arm64", "linux/arm64")],
                    value="linux/amd64",
                    id="platform"
                )
            
            with Vertical(classes="field"):
                yield Label("Build Args (KEY=VALUE, one per line):")
                yield Input(placeholder="BUILD_VERSION=1.0\nNODE_ENV=production", id="build_args")
            
            yield RichLog(id="output", wrap=True, markup=True)
            
            with Horizontal(classes="buttons"):
                yield Button("Cancel", variant="default", id="cancel")
                yield Button("Build", variant="success", id="build")
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss()
        elif event.button.id == "build":
            self.start_build()
    
    @work
    async def start_build(self) -> None:
        output = self.query_one("#output", RichLog)
        dockerfile = self.query_one("#dockerfile", Input).value
        context = self.query_one("#context", Input).value
        tag = self.query_one("#tag", Input).value
        platform = self.query_one("#platform", Select).value
        build_args_text = self.query_one("#build_args", Input).value
        
        if not tag:
            output.write("[red]Error: Tag is required[/red]")
            return
        
        build_args = {}
        for line in build_args_text.strip().split('\n'):
            if '=' in line:
                k, v = line.split('=', 1)
                build_args[k.strip()] = v.strip()
        
        if not DOCKER_AVAILABLE:
            output.write("[red]Docker not available[/red]")
            return
        
        output.write(f"[cyan]Building {tag}...[/cyan]")
        
        try:
            client = docker.from_env()
            image, logs = client.images.build(
                path=context,
                dockerfile=dockerfile,
                tag=tag,
                platform=platform,
                buildargs=build_args if build_args else None,
                rm=True,
                forcerm=True,
            )
            
            for chunk in logs:
                if 'stream' in chunk:
                    output.write(f"[dim]{chunk['stream'].strip()}[/dim]")
                elif 'error' in chunk:
                    output.write(f"[red]{chunk['error']}[/red]")
            
            output.write(f"[green]✓ Successfully built {image.short_id}[/green]")
            self.app.post_message(StatusMessage(f"Built image: {tag}", "success"))
            
        except Exception as e:
            output.write(f"[red]Build failed: {e}[/red]")

# ──────────────────────────────────────────────────────────────────────────────
# MAIN APP
# ──────────────────────────────────────────────────────────────────────────────

class DockerTUI(App):
    """Main Docker TUI Application."""
    
    TITLE = "Docker TUI"
    SUB_TITLE = "Container Management Interface"
    
    CSS = """
    Screen {
        background: $background;
    }
    
    Header {
        background: $primary;
        color: $text;
    }
    
    Footer {
        background: $surface;
        color: $text-muted;
    }
    
    /* Main layout */
    #main-grid {
        layout: grid;
        grid-size: 3;
        grid-rows: 1fr 1fr;
        grid-columns: 30% 70%;
        grid-gutter: 1;
        height: 1fr;
    }
    
    /* Sidebar */
    #sidebar {
        row-span: 2;
        border: solid $primary;
        background: $surface;
        padding: 1;
    }
    
    #sidebar .section {
        margin-bottom: 1;
    }
    
    #sidebar .section-title {
        color: $accent;
        text-style: bold;
        margin-bottom: 1;
        padding: 0 1;
    }
    
    #sidebar Tree {
        height: 1fr;
        background: transparent;
    }
    
    /* Resource panels */
    .resource-panel {
        border: solid $primary;
        background: $surface;
        height: 1fr;
    }
    
    .resource-panel .panel-header {
        height: 3;
        background: $primary;
        padding: 0 1;
        layout: horizontal;
        align: center middle;
    }
    
    .resource-panel .panel-title {
        color: $text;
        text-style: bold;
    }
    
    .resource-panel .panel-count {
        color: $text-muted;
        margin-left: 1;
    }
    
    .resource-panel .panel-actions {
        width: 1fr;
        content-align: right middle;
    }
    
    .resource-panel .panel-content {
        height: 1fr;
        padding: 1;
    }
    
    /* Data tables */
    DataTable {
        height: 1fr;
    }
    
    DataTable > .datatable--header {
        background: $boost;
        color: $text;
        text-style: bold;
    }
    
    DataTable > .datatable--cursor {
        background: $accent;
        color: $text;
    }
    
    /* Logs */
    RichLog {
        background: $background;
        border: solid $primary;
    }
    
    Log {
        background: $background;
        border: solid $primary;
    }
    
    /* Status bar */
    #status-bar {
        dock: bottom;
        height: 1;
        background: $surface;
        border-top: solid $primary;
        padding: 0 1;
        layout: horizontal;
    }
    
    #status-bar .status-left {
        width: 1fr;
    }
    
    #status-bar .status-center {
        width: 1fr;
        content-align: center middle;
    }
    
    #status-bar .status-right {
        width: 1fr;
        content-align: right middle;
    }
    
    /* Tabs */
    Tabs {
        background: $surface;
        border-bottom: solid $primary;
    }
    
    Tabs > .tab {
        color: $text-muted;
        padding: 0 2;
    }
    
    Tabs > .tab.--active {
        color: $accent;
        text-style: bold;
        border-bottom: solid $accent;
    }
    
    /* Modals */
    ModalScreen > Container {
        background: $surface;
        border: thick $primary;
    }
    
    /* Buttons */
    Button {
        margin: 0 1;
    }
    
    /* Inputs */
    Input, Select {
        border: solid $primary;
    }
    
    Input:focus, Select:focus {
        border: solid $accent;
    }
    
    /* Progress bars */
    ProgressBar {
        margin: 1 0;
    }
    """
    
    BINDINGS = [
        Binding("q", "quit", "Quit", show=True),
        Binding("r", "refresh", "Refresh", show=True),
        Binding("/", "focus_filter", "Filter", show=True),
        Binding("escape", "clear_filter", "Clear", show=False),
        Binding("enter", "select_resource", "Select", show=False),
        Binding("space", "toggle_resource", "Toggle", show=False),
        Binding("l", "show_logs", "Logs", show=True),
        Binding("s", "shell", "Shell", show=True),
        Binding("i", "inspect", "Inspect", show=True),
        Binding("d", "remove_resource", "Remove", show=True),
        Binding("p", "prune", "Prune", show=True),
        Binding("n", "new_container", "New", show=True),
        Binding("u", "pull_image", "Pull", show=True),
        Binding("b", "build_image", "Build", show=True),
        Binding("c", "compose_up", "Compose Up", show=True),
        Binding("x", "compose_down", "Compose Down", show=True),
        Binding("tab", "next_tab", "Next Tab", show=False),
        Binding("shift+tab", "prev_tab", "Prev Tab", show=False),
        Binding("f1", "help", "Help", show=True),
    ]
    
    # Reactive state
    current_tab: reactive[str] = reactive("containers")
    containers: reactive[list[ContainerInfo]] = reactive([])
    images: reactive[list[ImageInfo]] = reactive([])
    volumes: reactive[list[VolumeInfo]] = reactive([])
    networks: reactive[list[NetworkInfo]] = reactive([])
    compose_services: reactive[list[ComposeService]] = reactive([])
    selected_container: reactive[Optional[ContainerInfo]] = reactive(None)
    selected_image: reactive[Optional[ImageInfo]] = reactive(None)
    selected_volume: reactive[Optional[VolumeInfo]] = reactive(None)
    selected_network: reactive[Optional[NetworkInfo]] = reactive(None)
    filter_text: reactive[str] = reactive("")
    docker_client: Optional[docker.DockerClient] = None
    stats_task: Optional[asyncio.Task] = None
    update_count = 0
    
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        
        with Grid(id="main-grid"):
            # Sidebar
            with Container(id="sidebar"):
                yield Label("🐳 Docker Resources", classes="section-title")
                yield Tree("Resources", id="resource-tree")
                
                yield Label("📊 Quick Stats", classes="section-title")
                with Container(id="quick-stats"):
                    yield MetricCard("Containers", "0", "")
                    yield MetricCard("Images", "0", "")
                    yield MetricCard("Volumes", "0", "")
                    yield MetricCard("Networks", "0", "")
                
                yield Label("🔧 Actions", classes="section-title")
                with Vertical(id="quick-actions"):
                    yield Button("New Container", id="btn-new-container", variant="primary")
                    yield Button("Pull Image", id="btn-pull-image")
                    yield Button("Build Image", id="btn-build-image")
                    yield Button("Compose Up", id="btn-compose-up")
                    yield Button("Compose Down", id="btn-compose-down", variant="error")
                    yield Button("Prune All", id="btn-prune", variant="warning")
            
            # Containers Panel
            with Container(classes="resource-panel", id="containers-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("📦 Containers", classes="panel-title")
                    yield Label("(0)", classes="panel-count", id="containers-count")
                    with Horizontal(classes="panel-actions"):
                        yield FilterInput(placeholder="Filter containers...", id="containers-filter")
                        yield Button("Refresh", id="btn-refresh-containers", variant="primary")
                with Container(classes="panel-content"):
                    yield DataTable(id="containers-table", cursor_type="row")
            
            # Images Panel
            with Container(classes="resource-panel", id="images-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("🖼️ Images", classes="panel-title")
                    yield Label("(0)", classes="panel-count", id="images-count")
                    with Horizontal(classes="panel-actions"):
                        yield FilterInput(placeholder="Filter images...", id="images-filter")
                        yield Button("Refresh", id="btn-refresh-images", variant="primary")
                        yield Button("Pull", id="btn-pull-image-panel", variant="success")
                        yield Button("Build", id="btn-build-image-panel", variant="primary")
                with Container(classes="panel-content"):
                    yield DataTable(id="images-table", cursor_type="row")
            
            # Volumes Panel
            with Container(classes="resource-panel", id="volumes-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("💾 Volumes", classes="panel-title")
                    yield Label("(0)", classes="panel-count", id="volumes-count")
                    with Horizontal(classes="panel-actions"):
                        yield FilterInput(placeholder="Filter volumes...", id="volumes-filter")
                        yield Button("Refresh", id="btn-refresh-volumes", variant="primary")
                        yield Button("Create", id="btn-create-volume", variant="success")
                        yield Button("Prune", id="btn-prune-volumes", variant="warning")
                with Container(classes="panel-content"):
                    yield DataTable(id="volumes-table", cursor_type="row")
            
            # Networks Panel
            with Container(classes="resource-panel", id="networks-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("🌐 Networks", classes="panel-title")
                    yield Label("(0)", classes="panel-count", id="networks-count")
                    with Horizontal(classes="panel-actions"):
                        yield FilterInput(placeholder="Filter networks...", id="networks-filter")
                        yield Button("Refresh", id="btn-refresh-networks", variant="primary")
                        yield Button("Create", id="btn-create-network", variant="success")
                        yield Button("Prune", id="btn-prune-networks", variant="warning")
                with Container(classes="panel-content"):
                    yield DataTable(id="networks-table", cursor_type="row")
            
            # Compose Panel
            with Container(classes="resource-panel", id="compose-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("📋 Compose", classes="panel-title")
                    yield Label("(0)", classes="panel-count", id="compose-count")
                    with Horizontal(classes="panel-actions"):
                        yield FilterInput(placeholder="Filter services...", id="compose-filter")
                        yield Button("Refresh", id="btn-refresh-compose", variant="primary")
                        yield Button("Up", id="btn-compose-up-panel", variant="success")
                        yield Button("Down", id="btn-compose-down-panel", variant="error")
                        yield Button("Logs", id="btn-compose-logs")
                with Container(classes="panel-content"):
                    yield DataTable(id="compose-table", cursor_type="row")
            
            # Logs/Details Panel (bottom right area - will be tabbed)
            with Container(classes="resource-panel", id="details-panel"):
                with Horizontal(classes="panel-header"):
                    yield Label("📋 Details / Logs", classes="panel-title")
                    with Horizontal(classes="panel-actions"):
                        yield Button("Follow", id="btn-follow-logs", variant="primary")
                        yield Button("Clear", id="btn-clear-logs")
                with Container(classes="panel-content"):
                    with TabbedContent(id="details-tabs"):
                        with TabPane("Logs", id="tab-logs"):
                            yield RichLog(id="logs", auto_scroll=True, wrap=True, markup=True)
                        with TabPane("Inspect", id="tab-inspect"):
                            yield RichLog(id="inspect", wrap=True, markup=True)
                        with TabPane("Stats", id="tab-stats"):
                            yield Static(id="stats-content")
        
        # Status bar
        with Horizontal(id="status-bar"):
            yield Label("Ready", id="status-left", classes="status-left")
            yield Label("", id="status-center", classes="status-center")
            yield Label("F1: Help | /: Filter | Enter: Select | L: Logs | S: Shell | I: Inspect | D: Remove", id="status-right", classes="status-right")
        
        yield Footer()
    
    def on_mount(self) -> None:
        """Initialize the app."""
        self.setup_docker()
        self.setup_tables()
        self.setup_resource_tree()
        self.start_stats_updates()
        self.refresh_all_data()
    
    def setup_docker(self) -> None:
        """Initialize Docker client."""
        if DOCKER_AVAILABLE:
            try:
                self.docker_client = docker.from_env()
                self.docker_client.ping()
                self.post_message(StatusMessage("Connected to Docker daemon", "success"))
            except Exception as e:
                self.post_message(StatusMessage(f"Docker connection failed: {e}", "error"))
                self.docker_client = None
        else:
            self.post_message(StatusMessage("Docker SDK not installed (pip install docker)", "warning"))
    
    def setup_tables(self) -> None:
        """Setup data table columns."""
        # Containers table
        ct = self.query_one("#containers-table", DataTable)
        ct.add_columns("NAME", "IMAGE", "STATUS", "PORTS", "CPU%", "MEM%", "CREATED")
        
        # Images table
        it = self.query_one("#images-table", DataTable)
        it.add_columns("REPOSITORY", "TAG", "IMAGE ID", "SIZE", "CREATED")
        
        # Volumes table
        vt = self.query_one("#volumes-table", DataTable)
        vt.add_columns("NAME", "DRIVER", "MOUNTPOINT", "SCOPE")
        
        # Networks table
        nt = self.query_one("#networks-table", DataTable)
        nt.add_columns("NAME", "ID", "DRIVER", "SCOPE")
        
        # Compose table
        cpt = self.query_one("#compose-table", DataTable)
        cpt.add_columns("NAME", "STATUS", "IMAGE", "PORTS")
    
    def setup_resource_tree(self) -> None:
        """Setup the resource tree in sidebar."""
        tree = self.query_one("#resource-tree", Tree)
        tree.root.expand()
        
        containers_node = tree.root.add("📦 Containers", expand=True)
        containers_node.add_leaf("Running")
        containers_node.add_leaf("Stopped")
        containers_node.add_leaf("All")
        
        images_node = tree.root.add("🖼️ Images", expand=True)
        images_node.add_leaf("All Images")
        images_node.add_leaf("Dangling")
        
        volumes_node = tree.root.add("💾 Volumes", expand=True)
        volumes_node.add_leaf("All Volumes")
        volumes_node.add_leaf("Unused")
        
        networks_node = tree.root.add("🌐 Networks", expand=True)
        networks_node.add_leaf("All Networks")
        
        compose_node = tree.root.add("📋 Compose", expand=True)
        compose_node.add_leaf("Services")
        compose_node.add_leaf("Configs")
        
        # Select containers by default
        tree.select_node(containers_node.children[0])
        self.current_tab = "containers"
    
    def start_stats_updates(self) -> None:
        """Start periodic stats updates."""
        self.stats_task = self.set_interval(5.0, self.update_container_stats)
        self.set_interval(10.0, self.refresh_all_data)
    
    def on_unmount(self) -> None:
        """Cleanup on exit."""
        if self.stats_task:
            self.stats_task.cancel()
    
    # ──────────────────────────────────────────────────────────────────────────
    # DATA REFRESH
    # ──────────────────────────────────────────────────────────────────────────
    
    @work
    async def refresh_all_data(self) -> None:
        """Refresh all Docker data."""
        self.update_count += 1
        self.query_one("#status-center", Label).update(f"Update #{self.update_count} • {datetime.now().strftime('%H:%M:%S')}")
        
        await asyncio.gather(
            self.refresh_containers(),
            self.refresh_images(),
            self.refresh_volumes(),
            self.refresh_networks(),
            self.refresh_compose(),
        )
        
        self.update_quick_stats()
        self.post_message(StatusMessage("Data refreshed", "success"))
    
    @work
    async def refresh_containers(self) -> None:
        """Refresh container list."""
        if not self.docker_client:
            return
        
        try:
            containers = self.docker_client.containers.list(all=True)
            self.containers = []
            
            for c in containers:
                attrs = c.attrs
                state = attrs.get('State', {})
                network_settings = attrs.get('NetworkSettings', {})
                ports = network_settings.get('Ports', {})
                
                # Format ports
                port_strs = []
                for container_port, host_bindings in ports.items():
                    if host_bindings:
                        for binding in host_bindings:
                            host_port = binding.get('HostPort', '')
                            host_ip = binding.get('HostIp', '0.0.0.0')
                            if host_port:
                                port_strs.append(f"{host_ip}:{host_port}->{container_port}")
                    else:
                        port_strs.append(container_port)
                
                # Get resource stats if running
                cpu_pct = 0.0
                mem_pct = 0.0
                mem_usage = ""
                mem_limit = ""
                net_io = ""
                block_io = ""
                pids = 0
                
                if state.get('Running'):
                    try:
                        stats = c.stats(stream=False)
                        # CPU
                        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                                   stats['precpu_stats']['cpu_usage']['total_usage']
                        system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                                      stats['precpu_stats']['system_cpu_usage']
                        if system_delta > 0:
                            cpu_pct = (cpu_delta / system_delta) * 100.0
                        
                        # Memory
                        mem_usage_bytes = stats['memory_stats'].get('usage', 0)
                        mem_limit_bytes = stats['memory_stats'].get('limit', 0)
                        if mem_limit_bytes > 0:
                            mem_pct = (mem_usage_bytes / mem_limit_bytes) * 100.0
                            mem_usage = self._format_bytes(mem_usage_bytes)
                            mem_limit = self._format_bytes(mem_limit_bytes)
                        
                        # Network I/O
                        net_rx = sum(v['rx_bytes'] for v in stats.get('networks', {}).values())
                        net_tx = sum(v['tx_bytes'] for v in stats.get('networks', {}).values())
                        net_io = f"{self._format_bytes(net_rx)}/{self._format_bytes(net_tx)}"
                        
                        # Block I/O
                        blk_read = sum(v['value'] for v in stats.get('blkio_stats', {}).get('io_service_bytes_recursive', []) if v['op'] == 'Read')
                        blk_write = sum(v['value'] for v in stats.get('blkio_stats', {}).get('io_service_bytes_recursive', []) if v['op'] == 'Write')
                        block_io = f"{self._format_bytes(blk_read)}/{self._format_bytes(blk_write)}"
                        
                        pids = stats.get('pids_stats', {}).get('current', 0)
                    except:
                        pass
                
                created = attrs.get('Created', '')[:19].replace('T', ' ')
                
                self.containers.append(ContainerInfo(
                    id=c.short_id,
                    name=c.name,
                    image=attrs.get('Config', {}).get('Image', ''),
                    status=state.get('Status', 'unknown'),
                    state=state.get('Status', 'unknown'),
                    ports=", ".join(port_strs) if port_strs else "",
                    created=created,
                    cpu_percent=cpu_pct,
                    mem_percent=mem_pct,
                    mem_usage=mem_usage,
                    mem_limit=mem_limit,
                    net_io=net_io,
                    block_io=block_io,
                    pids=pids,
                ))
            
            self.populate_containers_table()
        except Exception as e:
            self.post_message(StatusMessage(f"Failed to refresh containers: {e}", "error"))
    
    @work
    async def refresh_images(self) -> None:
        """Refresh image list."""
        if not self.docker_client:
            return
        
        try:
            images = self.docker_client.images.list()
            self.images = []
            
            for img in images:
                tags = img.tags
                if tags:
                    for tag in tags:
                        if ':' in tag:
                            repo, tag = tag.rsplit(':', 1)
                        else:
                            repo, tag = tag, 'latest'
                        self.images.append(ImageInfo(
                            id=img.short_id,
                            repository=repo,
                            tag=tag,
                            size=self._format_bytes(img.attrs.get('Size', 0)),
                            created=img.attrs.get('Created', '')[:19].replace('T', ' '),
                            digest=img.attrs.get('RepoDigests', [''])[0] if img.attrs.get('RepoDigests') else "",
                        ))
                else:
                    # Untagged image
                    self.images.append(ImageInfo(
                        id=img.short_id,
                        repository="<none>",
                        tag="<none>",
                        size=self._format_bytes(img.attrs.get('Size', 0)),
                        created=img.attrs.get('Created', '')[:19].replace('T', ' '),
                    ))
            
            self.populate_images_table()
        except Exception as e:
            self.post_message(StatusMessage(f"Failed to refresh images: {e}", "error"))
    
    @work
    async def refresh_volumes(self) -> None:
        """Refresh volume list."""
        if not self.docker_client:
            return
        
        try:
            volumes = self.docker_client.volumes.list()
            self.volumes = []
            
            for v in volumes:
                attrs = v.attrs
                self.volumes.append(VolumeInfo(
                    name=v.name,
                    driver=attrs.get('Driver', 'local'),
                    mountpoint=attrs.get('Mountpoint', ''),
                    created=attrs.get('CreatedAt', '')[:19].replace('T', ' '),
                    scope=attrs.get('Scope', 'local'),
                ))
            
            self.populate_volumes_table()
        except Exception as e:
            self.post_message(StatusMessage(f"Failed to refresh volumes: {e}", "error"))
    
    @work
    async def refresh_networks(self) -> None:
        """Refresh network list."""
        if not self.docker_client:
            return
        
        try:
            networks = self.docker_client.networks.list()
            self.networks = []
            
            for n in networks:
                attrs = n.attrs
                self.networks.append(NetworkInfo(
                    id=n.short_id,
                    name=n.name,
                    driver=attrs.get('Driver', 'bridge'),
                    scope=attrs.get('Scope', 'local'),
                    created=attrs.get('Created', '')[:19].replace('T', ' '),
                ))
            
            self.populate_networks_table()
        except Exception as e:
            self.post_message(StatusMessage(f"Failed to refresh networks: {e}", "error"))
    
    @work
    async def refresh_compose(self) -> None:
        """Refresh compose services."""
        # Look for docker-compose files
        self.compose_services = []
        
        for compose_file in ['docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml']:
            path = Path.cwd() / compose_file
            if path.exists():
                try:
                    # Use docker compose CLI
                    import subprocess
                    result = subprocess.run(
                        ['docker', 'compose', '-f', str(path), 'ps', '--format', 'json'],
                        capture_output=True, text=True, timeout=10
                    )
                    if result.returncode == 0:
                        for line in result.stdout.strip().split('\n'):
                            if line:
                                svc = json.loads(line)
                                self.compose_services.append(ComposeService(
                                    name=svc.get('Name', ''),
                                    status=svc.get('State', ''),
                                    image=svc.get('Image', ''),
                                    ports=svc.get('Ports', ''),
                                ))
                except:
                    pass
        
        self.populate_compose_table()
    
    def update_quick_stats(self) -> None:
        """Update quick stats in sidebar."""
        running = sum(1 for c in self.containers if c.state == 'running')
        self.query_one("#quick-stats").query(MetricCard)[0].update_value(f"{running}/{len(self.containers)}")
        self.query_one("#quick-stats").query(MetricCard)[1].update_value(str(len(self.images)))
        self.query_one("#quick-stats").query(MetricCard)[2].update_value(str(len(self.volumes)))
        self.query_one("#quick-stats").query(MetricCard)[3].update_value(str(len(self.networks)))
    
    def _format_bytes(self, bytes_val: int) -> str:
        """Format bytes to human readable."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_val < 1024:
                return f"{bytes_val:.1f}{unit}"
            bytes_val /= 1024
        return f"{bytes_val:.1f}PB"
    
    # ──────────────────────────────────────────────────────────────────────────
    # TABLE POPULATION
    # ──────────────────────────────────────────────────────────────────────────
    
    def populate_containers_table(self) -> None:
        """Populate containers table."""
        table = self.query_one("#containers-table", DataTable)
        table.clear()
        
        filter_text = self.query_one("#containers-filter", FilterInput).value.lower()
        
        for c in self.containers:
            if filter_text and filter_text not in c.name.lower() and filter_text not in c.image.lower():
                continue
            
            status_badge = c.state.capitalize()
            row = [
                c.name,
                c.image.split(':')[0] if ':' in c.image else c.image,
                status_badge,
                c.ports or "-",
                f"{c.cpu_percent:.1f}%",
                f"{c.mem_percent:.1f}%",
                c.created,
            ]
            table.add_row(*row, key=c.id)
        
        self.query_one("#containers-count", Label).update(f"({table.row_count})")
    
    def populate_images_table(self) -> None:
        """Populate images table."""
        table = self.query_one("#images-table", DataTable)
        table.clear()
        
        filter_text = self.query_one("#images-filter", FilterInput).value.lower()
        
        for img in self.images:
            if filter_text and filter_text not in img.repository.lower() and filter_text not in img.tag.lower():
                continue
            
            row = [
                img.repository,
                img.tag,
                img.id,
                img.size,
                img.created,
            ]
            table.add_row(*row, key=img.id)
        
        self.query_one("#images-count", Label).update(f"({table.row_count})")
    
    def populate_volumes_table(self) -> None:
        """Populate volumes table."""
        table = self.query_one("#volumes-table", DataTable)
        table.clear()
        
        filter_text = self.query_one("#volumes-filter", FilterInput).value.lower()
        
        for v in self.volumes:
            if filter_text and filter_text not in v.name.lower():
                continue
            
            row = [v.name, v.driver, v.mountpoint, v.scope]
            table.add_row(*row, key=v.name)
        
        self.query_one("#volumes-count", Label).update(f"({table.row_count})")
    
    def populate_networks_table(self) -> None:
        """Populate networks table."""
        table = self.query_one("#networks-table", DataTable)
        table.clear()
        
        filter_text = self.query_one("#networks-filter", FilterInput).value.lower()
        
        for n in self.networks:
            if filter_text and filter_text not in n.name.lower():
                continue
            
            row = [n.name, n.id, n.driver, n.scope]
            table.add_row(*row, key=n.id)
        
        self.query_one("#networks-count", Label).update(f"({table.row_count})")
    
    def populate_compose_table(self) -> None:
        """Populate compose table."""
        table = self.query_one("#compose-table", DataTable)
        table.clear()
        
        filter_text = self.query_one("#compose-filter", FilterInput).value.lower()
        
        for svc in self.compose_services:
            if filter_text and filter_text not in svc.name.lower():
                continue
            
            row = [svc.name, svc.status, svc.image, svc.ports]
            table.add_row(*row, key=svc.name)
        
        self.query_one("#compose-count", Label).update(f"({table.row_count})")
    
    # ──────────────────────────────────────────────────────────────────────────
    # EVENT HANDLERS
    # ──────────────────────────────────────────────────────────────────────────
    
    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Handle row selection in data tables."""
        table = event.data_table
        row_key = event.row_key
        
        if table.id == "containers-table" and self.containers:
            c = next((c for c in self.containers if c.id == str(row_key.value)), None)
            if c:
                self.selected_container = c
                self.show_container_details(c)
        
        elif table.id == "images-table" and self.images:
            img = next((i for i in self.images if i.id == str(row_key.value)), None)
            if img:
                self.selected_image = img
                self.show_image_details(img)
        
        elif table.id == "volumes-table" and self.volumes:
            v = next((v for v in self.volumes if v.name == str(row_key.value)), None)
            if v:
                self.selected_volume = v
                self.show_volume_details(v)
        
        elif table.id == "networks-table" and self.networks:
            n = next((n for n in self.networks if n.id == str(row_key.value)), None)
            if n:
                self.selected_network = n
                self.show_network_details(n)
        
        elif table.id == "compose-table" and self.compose_services:
            svc = next((s for s in self.compose_services if s.name == str(row_key.value)), None)
            if svc:
                self.show_compose_service_details(svc)
    
    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle filter input changes."""
        if event.input.id == "containers-filter":
            self.populate_containers_table()
        elif event.input.id == "images-filter":
            self.populate_images_table()
        elif event.input.id == "volumes-filter":
            self.populate_volumes_table()
        elif event.input.id == "networks-filter":
            self.populate_networks_table()
        elif event.input.id == "compose-filter":
            self.populate_compose_table()
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        btn_id = event.button.id
        
        # Quick actions
        if btn_id == "btn-new-container":
            self.action_new_container()
        elif btn_id == "btn-pull-image" or btn_id == "btn-pull-image-panel":
            self.action_pull_image()
        elif btn_id == "btn-build-image" or btn_id == "btn-build-image-panel":
            self.action_build_image()
        elif btn_id == "btn-compose-up" or btn_id == "btn-compose-up-panel":
            self.action_compose_up()
        elif btn_id == "btn-compose-down" or btn_id == "btn-compose-down-panel":
            self.action_compose_down()
        elif btn_id == "btn-prune" or btn_id == "btn-prune-volumes" or btn_id == "btn-prune-networks":
            self.action_prune()
        elif btn_id == "btn-create-volume":
            self.action_create_volume()
        elif btn_id == "btn-create-network":
            self.action_create_network()
        
        # Refresh buttons
        elif btn_id == "btn-refresh-containers":
            self.refresh_containers()
        elif btn_id == "btn-refresh-images":
            self.refresh_images()
        elif btn_id == "btn-refresh-volumes":
            self.refresh_volumes()
        elif btn_id == "btn-refresh-networks":
            self.refresh_networks()
        elif btn_id == "btn-refresh-compose":
            self.refresh_compose()
        
        # Logs buttons
        elif btn_id == "btn-follow-logs":
            self.toggle_follow_logs()
        elif btn_id == "btn-clear-logs":
            self.query_one("#logs", RichLog).clear()
    
    def on_tree_node_selected(self, event: Tree.NodeSelected) -> None:
        """Handle tree selection."""
        node = event.node
        label = node.label.plain if hasattr(node.label, 'plain') else str(node.label)
        
        # Map tree selection to tabs
        tab_map = {
            "Running": ("containers", "running"),
            "Stopped": ("containers", "stopped"),
            "All": ("containers", "all"),
            "All Images": ("images", "all"),
            "Dangling": ("images", "dangling"),
            "All Volumes": ("volumes", "all"),
            "Unused": ("volumes", "unused"),
            "All Networks": ("networks", "all"),
            "Services": ("compose", "services"),
            "Configs": ("compose", "configs"),
        }
        
        if label in tab_map:
            tab, filter_type = tab_map[label]
            self.switch_tab(tab)
            # Apply filter if needed
    
    # ──────────────────────────────────────────────────────────────────────────
    # ACTIONS
    # ──────────────────────────────────────────────────────────────────────────
    
    def action_refresh(self) -> None:
        """Refresh current tab data."""
        self.refresh_all_data()
    
    def action_focus_filter(self) -> None:
        """Focus the filter input for current tab."""
        filter_map = {
            "containers": "#containers-filter",
            "images": "#images-filter",
            "volumes": "#volumes-filter",
            "networks": "#networks-filter",
            "compose": "#compose-filter",
        }
        if self.current_tab in filter_map:
            self.query_one(filter_map[self.current_tab], FilterInput).focus()
    
    def action_clear_filter(self) -> None:
        """Clear current filter."""
        filter_map = {
            "containers": "#containers-filter",
            "images": "#images-filter",
            "volumes": "#volumes-filter",
            "networks": "#networks-filter",
            "compose": "#compose-filter",
        }
        if self.current_tab in filter_map:
            inp = self.query_one(filter_map[self.current_tab], FilterInput)
            inp.value = ""
            inp.blur()
    
    def action_select_resource(self) -> None:
        """Select current resource (enter key)."""
        # Already handled by row selection
        pass
    
    def action_toggle_resource(self) -> None:
        """Toggle resource state (start/stop)."""
        if self.current_tab == "containers" and self.selected_container:
            c = self.selected_container
            if c.state == "running":
                self.stop_container(c)
            else:
                self.start_container(c)
    
    def action_show_logs(self) -> None:
        """Show logs for selected container."""
        if self.selected_container:
            self.show_logs_screen(self.selected_container)
    
    def action_shell(self) -> None:
        """Open shell in container."""
        if self.selected_container:
            self.open_shell(self.selected_container)
    
    def action_inspect(self) -> None:
        """Inspect selected resource."""
        if self.current_tab == "containers" and self.selected_container:
            self.show_inspect("Container", self.selected_container.id, self.docker_client.containers.get(self.selected_container.id).attrs)
        elif self.current_tab == "images" and self.selected_image:
            self.show_inspect("Image", self.selected_image.id, self.docker_client.images.get(self.selected_image.id).attrs)
        elif self.current_tab == "volumes" and self.selected_volume:
            self.show_inspect("Volume", self.selected_volume.name, self.docker_client.volumes.get(self.selected_volume.name).attrs)
        elif self.current_tab == "networks" and self.selected_network:
            self.show_inspect("Network", self.selected_network.id, self.docker_client.networks.get(self.selected_network.id).attrs)
    
    def action_remove_resource(self) -> None:
        """Remove selected resource."""
        if self.current_tab == "containers" and self.selected_container:
            self.confirm_remove_container(self.selected_container)
        elif self.current_tab == "images" and self.selected_image:
            self.confirm_remove_image(self.selected_image)
        elif self.current_tab == "volumes" and self.selected_volume:
            self.confirm_remove_volume(self.selected_volume)
        elif self.current_tab == "networks" and self.selected_network:
            self.confirm_remove_network(self.selected_network)
    
    def action_prune(self) -> None:
        """Prune unused resources."""
        self.confirm_prune()
    
    def action_new_container(self) -> None:
        """Create new container (run image)."""
        self.show_run_container_dialog()
    
    def action_pull_image(self) -> None:
        """Pull image dialog."""
        self.show_pull_image_dialog()
    
    def action_build_image(self) -> None:
        """Build image dialog."""
        self.push_screen(BuildImageScreen())
    
    def action_compose_up(self) -> None:
        """Docker compose up."""
        self.run_compose_command("up -d")
    
    def action_compose_down(self) -> None:
        """Docker compose down."""
        self.run_compose_command("down")
    
    def action_next_tab(self) -> None:
        """Switch to next tab."""
        tabs = ["containers", "images", "volumes", "networks", "compose"]
        idx = tabs.index(self.current_tab) if self.current_tab in tabs else 0
        self.switch_tab(tabs[(idx + 1) % len(tabs)])
    
    def action_prev_tab(self) -> None:
        """Switch to previous tab."""
        tabs = ["containers", "images", "volumes", "networks", "compose"]
        idx = tabs.index(self.current_tab) if self.current_tab in tabs else 0
        self.switch_tab(tabs[(idx - 1) % len(tabs)])
    
    def action_help(self) -> None:
        """Show help."""
        self.show_help()
    
    def switch_tab(self, tab: str) -> None:
        """Switch to a tab."""
        self.current_tab = tab
        # Update UI to show appropriate panel
        # For now, all panels are visible in grid
    
    # ──────────────────────────────────────────────────────────────────────────
    # CONTAINER OPERATIONS
    # ──────────────────────────────────────────────────────────────────────────
    
    def start_container(self, container: ContainerInfo) -> None:
        """Start a container."""
        if not self.docker_client:
            return
        
        @work
        async def do_start() -> None:
            try:
                c = self.docker_client.containers.get(container.id)
                c.start()
                self.post_message(StatusMessage(f"Started {container.name}", "success"))
                self.refresh_containers()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to start: {e}", "error"))
        
        do_start()
    
    def stop_container(self, container: ContainerInfo) -> None:
        """Stop a container."""
        if not self.docker_client:
            return
        
        @work
        async def do_stop() -> None:
            try:
                c = self.docker_client.containers.get(container.id)
                c.stop(timeout=10)
                self.post_message(StatusMessage(f"Stopped {container.name}", "success"))
                self.refresh_containers()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to stop: {e}", "error"))
        
        do_stop()
    
    def confirm_remove_container(self, container: ContainerInfo) -> None:
        """Confirm container removal."""
        self.push_screen(
            ConfirmDialog(
                f"Remove container '{container.name}' ({container.id})?\n"
                f"Image: {container.image}",
                "Remove Container"
            ),
            lambda confirmed: confirmed and self.remove_container(container)
        )
    
    def remove_container(self, container: ContainerInfo) -> None:
        """Remove a container."""
        if not self.docker_client:
            return
        
        @work
        async def do_remove() -> None:
            try:
                c = self.docker_client.containers.get(container.id)
                c.remove(force=True)
                self.post_message(StatusMessage(f"Removed {container.name}", "success"))
                self.refresh_containers()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to remove: {e}", "error"))
        
        do_remove()
    
    def confirm_remove_image(self, image: ImageInfo) -> None:
        """Confirm image removal."""
        self.push_screen(
            ConfirmDialog(
                f"Remove image '{image.repository}:{image.tag}' ({image.id})?",
                "Remove Image"
            ),
            lambda confirmed: confirmed and self.remove_image(image)
        )
    
    def remove_image(self, image: ImageInfo) -> None:
        """Remove an image."""
        if not self.docker_client:
            return
        
        @work
        async def do_remove() -> None:
            try:
                self.docker_client.images.remove(f"{image.repository}:{image.tag}", force=True)
                self.post_message(StatusMessage(f"Removed {image.repository}:{image.tag}", "success"))
                self.refresh_images()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to remove: {e}", "error"))
        
        do_remove()
    
    def confirm_remove_volume(self, volume: VolumeInfo) -> None:
        """Confirm volume removal."""
        self.push_screen(
            ConfirmDialog(
                f"Remove volume '{volume.name}'?\n"
                f"Driver: {volume.driver}\nMountpoint: {volume.mountpoint}",
                "Remove Volume"
            ),
            lambda confirmed: confirmed and self.remove_volume(volume)
        )
    
    def remove_volume(self, volume: VolumeInfo) -> None:
        """Remove a volume."""
        if not self.docker_client:
            return
        
        @work
        async def do_remove() -> None:
            try:
                self.docker_client.volumes.get(volume.name).remove()
                self.post_message(StatusMessage(f"Removed volume {volume.name}", "success"))
                self.refresh_volumes()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to remove: {e}", "error"))
        
        do_remove()
    
    def confirm_remove_network(self, network: NetworkInfo) -> None:
        """Confirm network removal."""
        self.push_screen(
            ConfirmDialog(
                f"Remove network '{network.name}' ({network.id})?\n"
                f"Driver: {network.driver}",
                "Remove Network"
            ),
            lambda confirmed: confirmed and self.remove_network(network)
        )
    
    def remove_network(self, network: NetworkInfo) -> None:
        """Remove a network."""
        if not self.docker_client:
            return
        
        @work
        async def do_remove() -> None:
            try:
                self.docker_client.networks.get(network.id).remove()
                self.post_message(StatusMessage(f"Removed network {network.name}", "success"))
                self.refresh_networks()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to remove: {e}", "error"))
        
        do_remove()
    
    def confirm_prune(self) -> None:
        """Confirm prune all."""
        self.push_screen(
            ConfirmDialog(
                "This will remove:\n"
                "• All stopped containers\n"
                "• All unused networks\n"
                "• All dangling images\n"
                "• All unused volumes\n\n"
                "Are you sure?",
                "Prune All Unused Resources"
            ),
            lambda confirmed: confirmed and self.do_prune()
        )
    
    def do_prune(self) -> None:
        """Execute prune."""
        if not self.docker_client:
            return
        
        @work
        async def do_prune() -> None:
            try:
                result = self.docker_client.containers.prune()
                self.post_message(StatusMessage(f"Pruned containers: {result['ContainersDeleted']}", "success"))
                
                result = self.docker_client.networks.prune()
                self.post_message(StatusMessage(f"Pruned networks: {result['NetworksDeleted']}", "success"))
                
                result = self.docker_client.images.prune()
                self.post_message(StatusMessage(f"Pruned images: {result['ImagesDeleted']}", "success"))
                
                result = self.docker_client.volumes.prune()
                self.post_message(StatusMessage(f"Pruned volumes: {result['VolumesDeleted']}", "success"))
                
                self.refresh_all_data()
            except Exception as e:
                self.post_message(StatusMessage(f"Prune failed: {e}", "error"))
        
        do_prune()
    
    def show_run_container_dialog(self) -> None:
        """Show dialog to run a new container."""
        self.push_screen(
            InputDialog(
                "Enter image name to run (e.g., nginx:alpine):",
                placeholder="nginx:alpine",
                default=""
            ),
            lambda image: image and self.run_container(image)
        )
    
    def run_container(self, image: str) -> None:
        """Run a container from image."""
        if not self.docker_client:
            return
        
        @work
        async def do_run() -> None:
            try:
                self.docker_client.containers.run(image, detach=True)
                self.post_message(StatusMessage(f"Started container from {image}", "success"))
                self.refresh_containers()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to run: {e}", "error"))
        
        do_run()
    
    def show_pull_image_dialog(self) -> None:
        """Show dialog to pull image."""
        self.push_screen(
            InputDialog(
                "Enter image name to pull (e.g., nginx:latest):",
                placeholder="nginx:latest",
                default=""
            ),
            lambda image: image and self.pull_image(image)
        )
    
    def pull_image(self, image: str) -> None:
        """Pull an image."""
        if not self.docker_client:
            return
        
        @work
        async def do_pull() -> None:
            try:
                self.post_message(StatusMessage(f"Pulling {image}...", "info"))
                self.docker_client.images.pull(image)
                self.post_message(StatusMessage(f"Pulled {image}", "success"))
                self.refresh_images()
            except Exception as e:
                self.post_message(StatusMessage(f"Pull failed: {e}", "error"))
        
        do_pull()
    
    def show_create_volume_dialog(self) -> None:
        """Show dialog to create volume."""
        self.push_screen(
            InputDialog(
                "Enter volume name:",
                placeholder="my-volume",
                default=""
            ),
            lambda name: name and self.create_volume(name)
        )
    
    def create_volume(self, name: str) -> None:
        """Create a volume."""
        if not self.docker_client:
            return
        
        @work
        async def do_create() -> None:
            try:
                self.docker_client.volumes.create(name=name)
                self.post_message(StatusMessage(f"Created volume {name}", "success"))
                self.refresh_volumes()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to create: {e}", "error"))
        
        do_create()
    
    def show_create_network_dialog(self) -> None:
        """Show dialog to create network."""
        self.push_screen(
            InputDialog(
                "Enter network name:",
                placeholder="my-network",
                default=""
            ),
            lambda name: name and self.create_network(name)
        )
    
    def create_network(self, name: str) -> None:
        """Create a network."""
        if not self.docker_client:
            return
        
        @work
        async def do_create() -> None:
            try:
                self.docker_client.networks.create(name, driver="bridge")
                self.post_message(StatusMessage(f"Created network {name}", "success"))
                self.refresh_networks()
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to create: {e}", "error"))
        
        do_create()
    
    def run_compose_command(self, cmd: str) -> None:
        """Run docker compose command."""
        @work
        async def do_compose() -> None:
            try:
                import subprocess
                result = subprocess.run(
                    ['docker', 'compose'] + cmd.split(),
                    capture_output=True, text=True, timeout=60
                )
                if result.returncode == 0:
                    self.post_message(StatusMessage(f"Compose {cmd} completed", "success"))
                else:
                    self.post_message(StatusMessage(f"Compose failed: {result.stderr}", "error"))
                self.refresh_compose()
            except Exception as e:
                self.post_message(StatusMessage(f"Compose failed: {e}", "error"))
        
        do_compose()
    
    # ──────────────────────────────────────────────────────────────────────────
    # DETAIL VIEWS
    # ──────────────────────────────────────────────────────────────────────────
    
    def show_container_details(self, container: ContainerInfo) -> None:
        """Show container details in inspect tab."""
        if not self.docker_client:
            return
        
        try:
            c = self.docker_client.containers.get(container.id)
            self.show_inspect("Container", container.id, c.attrs)
        except:
            pass
    
    def show_image_details(self, image: ImageInfo) -> None:
        """Show image details."""
        if not self.docker_client:
            return
        
        try:
            img = self.docker_client.images.get(image.id)
            self.show_inspect("Image", image.id, img.attrs)
        except:
            pass
    
    def show_volume_details(self, volume: VolumeInfo) -> None:
        """Show volume details."""
        if not self.docker_client:
            return
        
        try:
            v = self.docker_client.volumes.get(volume.name)
            self.show_inspect("Volume", volume.name, v.attrs)
        except:
            pass
    
    def show_network_details(self, network: NetworkInfo) -> None:
        """Show network details."""
        if not self.docker_client:
            return
        
        try:
            n = self.docker_client.networks.get(network.id)
            self.show_inspect("Network", network.id, n.attrs)
        except:
            pass
    
    def show_compose_service_details(self, service: ComposeService) -> None:
        """Show compose service details."""
        logs = self.query_one("#logs", RichLog)
        logs.clear()
        logs.write(f"[bold]Service: {service.name}[/bold]")
        logs.write(f"Status: {service.status}")
        logs.write(f"Image: {service.image}")
        logs.write(f"Ports: {service.ports or 'None'}")
    
    def show_inspect(self, resource_type: str, resource_id: str, data: dict) -> None:
        """Show inspect data in inspect tab."""
        self.query_one("#details-tabs", TabbedContent).active = "tab-inspect"
        self.show_inspect_screen(resource_type, resource_id, data)
    
    def show_inspect_screen(self, resource_type: str, resource_id: str, data: dict) -> None:
        """Show inspect modal."""
        self.push_screen(InspectScreen(f"{resource_type}: {resource_id}", data))
    
    def show_logs_screen(self, container: ContainerInfo) -> None:
        """Show logs modal."""
        self.query_one("#details-tabs", TabbedContent).active = "tab-logs"
        self.push_screen(LogsScreen(container.id, container.name))
    
    def toggle_follow_logs(self) -> None:
        """Toggle follow mode for logs."""
        # Handled in LogsScreen
        pass
    
    def open_shell(self, container: ContainerInfo) -> None:
        """Open shell in container."""
        if not self.docker_client:
            return
        
        @work
        async def do_shell() -> None:
            try:
                c = self.docker_client.containers.get(container.id)
                # Try different shells
                for shell in ['/bin/bash', '/bin/sh']:
                    try:
                        exec_result = c.exec_run(shell, tty=True, stdin=True, stdout=True, stderr=True)
                        break
                    except:
                        continue
                self.post_message(StatusMessage(f"Shell opened in {container.name}", "success"))
            except Exception as e:
                self.post_message(StatusMessage(f"Failed to open shell: {e}", "error"))
        
        do_shell()
    
    def update_container_stats(self) -> None:
        """Update container stats for running containers."""
        if not self.docker_client:
            return
        
        # Update the containers table with new stats
        self.refresh_containers()
    
    # ──────────────────────────────────────────────────────────────────────────
    # MESSAGES
    # ──────────────────────────────────────────────────────────────────────────
    
    def on_status_message(self, message: StatusMessage) -> None:
        """Handle status messages."""
        self.query_one("#status-left", Label).update(message.message)
        self.notify(message.message, severity=message.severity)
    
    # ──────────────────────────────────────────────────────────────────────────
    # HELP
    # ──────────────────────────────────────────────────────────────────────────
    
    def show_help(self) -> None:
        """Show help screen."""
        help_text = """
# Docker TUI - Keyboard Shortcuts

## Navigation
| Key | Action |
|-----|--------|
| `Tab` / `Shift+Tab` | Switch tabs |
| `/` | Focus filter |
| `Escape` | Clear filter |
| `↑/↓` | Navigate tables |
| `Enter` | Select row |

## Container Actions
| Key | Action |
|-----|--------|
| `Space` | Start/Stop container |
| `L` | Show logs |
| `S` | Open shell |
| `I` | Inspect |
| `D` | Remove |
| `R` | Restart (custom) |

## Image Actions
| Key | Action |
|-----|--------|
| `U` | Pull image |
| `B` | Build image |
| `I` | Inspect |
| `D` | Remove |

## Volume/Network
| Key | Action |
|-----|--------|
| `N` | Create new |
| `D` | Remove |
| `P` | Prune unused |

## Compose
| Key | Action |
|-----|--------|
| `C` | Compose Up |
| `X` | Compose Down |
| `L` | Compose Logs |

## Global
| Key | Action |
|-----|--------|
| `R` | Refresh all |
| `F1` | This help |
| `Q` | Quit |

## Mouse Support
- Click rows to select
- Click headers to sort
- Scroll in tables/logs
"""
        self.push_screen(InspectScreen("Help", {"help": help_text}))


# ──────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if not DOCKER_AVAILABLE:
        print("Docker SDK not installed. Install with: pip install docker")
        print("Some features will be limited.")
    
    app = DockerTUI()
    app.run()