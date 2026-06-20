# MQTT Examples

A collection of small, copy-pasteable examples that show how to send and receive
live data over **MQTT** straight from a web page (and from Godot and TouchDesigner too).

It is built for students who are **new to this**. No build tools, no frameworks, no
account to create. Open a file in your browser and it just works.

---

## What is this, in one minute?

**MQTT** is a tiny messaging system. Think of it like a group chat for devices and apps:

- A **broker** is the server everyone connects to (we use a free public one).
- A **topic** is like a chat channel, e.g. `sensor/value` or `mdd/color/red`.
- You can **publish** (send) a message to a topic.
- You can **subscribe** (listen) to a topic to get every message sent there.

Anyone connected to the same broker and topic sees the same messages. That is the whole
trick. A sensor on an Arduino, a slider on a web page, a phone tilting in your hand, and a
3D cube in Godot can all talk to each other just by agreeing on a topic name.

```
  [Arduino button]  --publish-->  topic: "button/1"  --subscribe-->  [web page]
  [phone tilt]      --publish-->  topic: "mobile/sensors/rotation" -->  [Godot plane]
```

The broker this project uses (no login needed):

```
wss://mqtt-public.xiduzo.com:443/mqtt
```

> ⚠️ It is **public**. Anyone can read and write any topic. Do not send anything private.
> Pick unusual topic names if you want a "private" channel during class.

---

## Getting started

### 1. Just look at the examples

The fastest path: **open `index.html` in your browser** (double-click it). The page
auto-connects to the broker — you should see "Connected" in the top bar — and lists every
example. Click any card to open it.

That is enough for most examples. Some examples need data coming in from somewhere
(a sensor, another browser tab, a phone) before anything visibly happens.

### 2. Run it with a local server (recommended)

A couple of examples (camera/phone motion) need to be served over `http://` instead of
opened as a `file://`. Run any tiny static server from the project folder:

```bash
# Python (already on most machines)
python3 -m http.server 8000

# or Node
npx serve
```

Then open <http://localhost:8000>.

### 3. Send your first message by hand

To really understand it, use a desktop MQTT client like **MQTTX** (free,
<https://mqttx.app>):

1. New connection → host `mqtt-public.xiduzo.com`, port `443`, path `/mqtt`, TLS on,
   protocol `wss`. (Same broker URL as the web pages: `wss://mqtt-public.xiduzo.com:443/mqtt`.)
2. Subscribe to `sensor/value`.
3. Open **Example 1** in the browser, then publish a number to `sensor/value` from MQTTX.
   Watch it appear on the page.

That round-trip — type a message, see a web page react — is the core idea of everything here.

---

## How the project is organized

```
index.html              Home page — auto-connects + links to every example
css/styles.css          Shared styling
js/
  mqtt-client.js        The shared MQTT wrapper used by every page (read this one!)
  main.js               Connect/disconnect buttons on the home page
  whiteboard.js         Extra logic for the shared-whiteboard example
pages/
  example1.html ...     One self-contained HTML file per example
  idea-generator.html   Slot machine that generates project prompts
godot/
  cube-mqtt/            Godot project: a 3D cube rotated over MQTT
  plane-mqtt/           Godot project: a plane flown by a phone over MQTT
touch-designer-canvas.toe   TouchDesigner patch (opens the shared whiteboard)
notes.MD                Teaching/demo script (the order to show things in class)
DEMO-IDEAS.md           Brainstormed ideas for more examples
```

### The one file to understand: `js/mqtt-client.js`

Every page loads this. It is a small object called `MQTTClient` that wraps the
[MQTT.js](https://github.com/mqttjs/MQTT.js) library and does three jobs:

- **Connects** to the broker automatically (`autoConnect: true`).
- Builds the **navbar** and **connection status** dot you see on every page.
- Gives you four simple hooks so each example stays tiny.

The four things you use in an example:

```js
MQTTClient.on('onConnect', () => {        // runs once connected
  MQTTClient.subscribe('my/topic');       // start listening to a topic
});

MQTTClient.on('onMessage', (topic, payload) => {  // runs on every message
  if (topic === 'my/topic') {
    console.log('got', payload);          // payload is always a string
  }
});

MQTTClient.publish('my/topic', 'hello');  // send a message
```

That is genuinely the whole API you need. Look at `pages/example1.html` — it is ~10 lines
of JavaScript and a great template to copy.

---

## The examples

| #  | Page                  | What it does                                                  | Topic(s) |
|----|-----------------------|--------------------------------------------------------------|----------|
| 1  | LDR Sensor            | Shows the latest value received, full screen                 | `sensor/value` |
| 2  | Day/Night Cycle       | Sun/moon move based on a sensor value                        | `sensor/value` |
| 3  | Windmill              | Windmill spins based on a wind/speed value                   | `mobile/sensors/rotation` |
| 4  | Mic Windmill          | Windmill driven by microphone loudness                       | `mobile/sensors/microphone` |
| 5  | RGB Color Mixer       | Sliders set the background colour for everyone               | `mdd/color/red`, `.../green`, `.../blue` |
| 6  | Shared Whiteboard     | Collaborative drawing canvas, synced live                    | whiteboard topics |
| 7  | Button                | Press a button → publishes a message                         | `button/1` |
| 8  | Phone-Flown Plane     | Tilt your phone to fly a three.js plane (open on your phone) | `mobile/sensors/rotation` |
| 9  | Platonic Solids       | Pick a solid; the choice syncs to every open screen          | `platonic/selected` |
| 🎰 | Idea Generator        | Spin to generate a project prompt for Figma Make             | — |

**Tip for seeing it "click":** open the same example in two browser windows (or on your
phone and laptop) at once. A change in one appears in the other, because both are
subscribed to the same topic on the same broker.

---

## Topic naming convention

Topics are just strings with `/` as separators. The ones used here group by purpose:

- `sensor/value` — a generic single sensor reading
- `mobile/sensors/...` — data coming from a phone (`rotation`, `microphone`)
- `mdd/color/...` — the RGB mixer channels
- `button/1` — a button press
- `platonic/selected` — which 3D solid is selected
- `cube/rotation/rotation` — rotation for the Godot cube

When you invent your own, pick a clear path like `myname/test/value` so it does not clash
with someone else on the public broker.

---

## Changing or adding an example

### Tweak an existing one
Open the matching file in `pages/`, edit the JavaScript at the bottom, save, refresh the
browser. No build step. Change the `TOPIC` string to listen to something else, or change
what happens in the `onMessage` callback.

### Add a brand-new example
1. **Copy a starting point.** Duplicate `pages/example1.html` → `pages/example10.html`.
   It already loads the MQTT library and the shared client for you.
2. **Write your logic** at the bottom `<script>` — subscribe to a topic, react to messages,
   and/or publish on a button click. (See the `MQTTClient` snippet above.)
3. **Add it to the home page.** In `index.html`, copy an `<a class="example-card">…</a>`
   block inside `.examples-grid` and point it at your new file.
4. **Add it to the dropdown menu.** In `js/mqtt-client.js`, add a line to the `navLinks`
   array (around line 107):
   ```js
   { href: 'pages/example10.html', label: 'My New Example' },
   ```
5. Refresh. Your example now shows on the home page and in the nav on every page.

### Test two-way live sync
Publish from one tab and subscribe in another (or use MQTTX). If both see the message,
your topic plumbing works — the rest is just deciding what to draw or do with the value.

---

## Godot examples

Inside `godot/` are two standalone [Godot 4](https://godotengine.org) projects that connect
to the **same broker** and react to the **same kinds of topics** as the web pages:

- `cube-mqtt/` — rotates a 3D cube from `cube/rotation/rotation`
- `plane-mqtt/` — fly a plane using your phone (Example 8 publishes the phone tilt)

Open the folder as a project in Godot and press Play. The broker/topic settings live in
`mqtt_config.gd`. This shows the point of MQTT nicely: the **same message** can drive a web
page *and* a game engine at once — they never need to know about each other.

## TouchDesigner

`touch-designer-canvas.toe` connects to the broker and mirrors the shared whiteboard
(Example 6). Open it in TouchDesigner to see web ↔ creative-tool data flow.

---

## Troubleshooting

- **Status dot stays "Disconnected".** Check your internet; the broker is online but you
  need network access. Open the browser console (F12) to see connection logs.
- **Nothing happens on the page.** Many examples only react when data arrives. Publish to
  the example's topic (table above) from another tab or MQTTX.
- **Phone/camera examples fail when double-clicked.** Serve them over `http://` with a
  local server (see "Getting started" step 2). Browsers block sensors on `file://`.
- **Two people clash on a topic.** The broker is public and shared. Use a unique topic name.

---

## Deployment

Pushing to `main` publishes the site to GitHub Pages automatically
(see `.github/workflows/static.yml`). Because everything is static files, the live site
behaves exactly like opening the files locally.

---

## Tech used

- [MQTT.js](https://github.com/mqttjs/MQTT.js) over WebSockets (loaded from a CDN)
- Plain HTML / CSS / JavaScript — no framework, no build step
- [three.js](https://threejs.org) for the 3D examples (8 & 9)
- Godot 4 and TouchDesigner for the non-web demos

Happy hacking — start by opening `index.html` and reading `pages/example1.html`.
