# Skill: TeeChart MCP Server

## Overview
This skill guides the AI assistant in utilizing the **TeeChart** Model Context Protocol (MCP) server. It enables the assistant to correctly interpret user requests, format data structures, and invoke the appropriate MCP tools to generate, configure, and customize charts seamlessly.

## Available Tools & Schemas

### 1. `create_chart`
Initializes a new standard Cartesian or general chart (e.g., line, bar, area).
- **Parameters:**
  - `type` (string, required): The chart type (`"line"`, `"bar"`, `"area"`, `"point"`).
  - `title` (string, optional): The main title displayed at the top of the chart.

### 2. `create_pie_chart`
Initializes and populates a specialized circular/pie chart.
- **Parameters:**
  - `title` (string, optional): The title of the pie chart.
  - `labels` (array of strings, required): Category names for each slice.
  - `values` (array of numbers, required): Numerical values corresponding to each slice.
  - `explode` (boolean, optional): Whether to visually separate slices.

### 3. `add_series`
Adds a data series to an existing generic chart context.
- **Parameters:**
  - `chart_id` (string, required): The identifier of the active chart.
  - `series_name` (string, optional): The legend name for the series.
  - `data` (JSON array or object, required): The formatted data points.

### 4. `set_properties`
Configures visual styling, axes, and formatting properties.
- **Parameters:**
  - `chart_id` (string, required): The identifier of the target chart.
  - `properties` (object, required): Key-value pairs of configurations (e.g., `{"legend": true, "grid_visible": false, "color_palette": "classic"}`).

---

## Usage Examples & Workflows

### Scenario A: Simple Line Chart
**User Request:** *"Can you generate a line chart showing monthly sales: Jan 120, Feb 150, Mar 170?"*

**AI Execution Flow:**
1. Call `create_chart` with:
   ```json
   {
     "type": "line",
     "title": "Monthly Sales"
   }
   ```
2. Call `add_series` with the structured data:
   ```json
   {
     "chart_id": "active_chart_1",
     "series_name": "Sales 2026",
     "data": [
       {"x": "Jan", "y": 120},
       {"x": "Feb", "y": 150},
       {"x": "Mar", "y": 170}
     ]
   }
   ```
3. Call `set_properties` to format axes if necessary.

### Scenario B: Pie Chart with Breakdown
**User Request:** *"Create a pie chart showing browser market share: Chrome 65%, Safari 20%, Firefox 15%."*

**AI Execution Flow:**
1. Call `create_pie_chart` with:
   ```json
   {
     "title": "Browser Market Share",
     "labels": ["Chrome", "Safari", "Firefox"],
     "values": [65, 20, 15],
     "explode": true
   }
   ```

---

## Best Practices & Rules
- **Data Validation:** Always ensure data arrays are formatted as valid JSON before invoking MCP tools.
- **Missing Parameters:** If required parameters (such as values or labels) are missing from the user's prompt, ask clarifying questions *before* executing the tool call.
- **Error Handling:** If the MCP server returns a schema or validation error, analyze the message, correct the payload structure, and retry or inform the user clearly.
