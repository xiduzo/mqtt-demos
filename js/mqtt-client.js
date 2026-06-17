// MQTT Client Configuration and Connection Manager
const MQTTClient = {
    autoConnect: true,
    client: null,
    config: {
        brokerUrl: 'wss://mqtt-public.xiduzo.com:443/mqtt',
        options: {
            clientId: 'mqtt_web_' + Math.random().toString(16).substring(2, 10),
            clean: true,
            reconnectPeriod: 5000,
            connectTimeout: 10000,
        }
    },
    
    callbacks: {
        onConnect: [],
        onDisconnect: [],
        onMessage: [],
        onError: []
    },

    connect() {
        if (this.client && this.client.connected) {
            console.log('Already connected');
            return;
        }

        console.log('Connecting to:', this.config.brokerUrl);
        this.client = mqtt.connect(this.config.brokerUrl, this.config.options);

        this.client.on('connect', () => {
            console.log('Connected to MQTT broker');
            this.callbacks.onConnect.forEach(cb => cb());
        });

        this.client.on('close', () => {
            console.log('Disconnected from MQTT broker');
            this.callbacks.onDisconnect.forEach(cb => cb());
        });

        this.client.on('message', (topic, message) => {
            const payload = message.toString();
            console.log('Message received:', topic, payload);
            this.callbacks.onMessage.forEach(cb => cb(topic, payload));
        });

        this.client.on('error', (error) => {
            console.error('MQTT Error:', error);
            this.callbacks.onError.forEach(cb => cb(error));
        });
    },

    disconnect() {
        if (this.client) {
            this.client.end();
            this.client = null;
        }
    },

    subscribe(topic, options = {}) {
        if (!this.client || !this.client.connected) {
            console.error('Not connected to broker');
            return false;
        }
        this.client.subscribe(topic, options, (err) => {
            if (err) console.error('Subscribe error:', err);
            else console.log('Subscribed to:', topic);
        });
        return true;
    },

    publish(topic, message, options = {}) {
        if (!this.client || !this.client.connected) {
            console.error('Not connected to broker');
            return false;
        }
        this.client.publish(topic, message, options);
        console.log('Published to:', topic, message);
        return true;
    },

    unsubscribe(topic) {
        if (this.client) {
            this.client.unsubscribe(topic);
        }
    },

    isConnected() {
        return this.client && this.client.connected;
    },

    on(event, callback) {
        if (this.callbacks[event]) {
            this.callbacks[event].push(callback);
        }
    },

    off(event, callback) {
        if (this.callbacks[event]) {
            const index = this.callbacks[event].indexOf(callback);
            if (index > -1) {
                this.callbacks[event].splice(index, 1);
            }
        }
    },

    navLinks: [
        { href: 'index.html', label: 'Home' },
        { href: 'pages/example1.html', label: 'LDR Sensor' },
        { href: 'pages/example2.html', label: 'Day/Night Cycle' },
        { href: 'pages/example3.html', label: 'Windmill' },
        { href: 'pages/example4.html', label: 'Mic Windmill' },
        { href: 'pages/example5.html', label: 'RGB Color Mixer' },
        { href: 'pages/example6.html', label: 'Shared Whiteboard' },
        { href: 'pages/example7.html', label: 'Button' },
        { href: 'pages/example8.html', label: 'Phone-Flown Plane' },
        { href: 'pages/example9.html', label: 'Platonic Solids' },
    ],

    init() {
        // Build navbar dynamically
        this.buildNavbar();
        
        // Setup global status indicator
        this.setupStatusIndicator();
        
        // Auto-connect if enabled
        if (this.autoConnect) {
            this.connect();
        }
    },

    buildNavbar() {
        const navbar = document.querySelector('.navbar');
        if (!navbar) return;

        // Determine if we're in a subdirectory
        const isSubpage = window.location.pathname.includes('/pages/');
        const currentPage = window.location.pathname.split('/').pop() || 'index.html';

        // Adjust an href for the current location (root vs /pages/)
        const adjust = (href) => {
            if (!isSubpage) return href;
            return href.startsWith('pages/') ? href.replace('pages/', '') : '../' + href;
        };

        // Brand doubles as the Home link
        const brand = navbar.querySelector('.nav-brand');
        if (brand && brand.tagName !== 'A') {
            const a = document.createElement('a');
            a.className = 'nav-brand';
            a.href = adjust('index.html');
            a.textContent = brand.textContent;
            brand.replaceWith(a);
        }

        // Clear existing nav-links
        const existingLinks = navbar.querySelector('.nav-links');
        if (existingLinks) existingLinks.remove();

        // Everything except Home goes into a dropdown (the list got long)
        const exampleLinks = this.navLinks.filter(l => l.href !== 'index.html');

        const ul = document.createElement('ul');
        ul.className = 'nav-links';

        const li = document.createElement('li');
        li.className = 'nav-dropdown';

        const toggle = document.createElement('button');
        toggle.className = 'nav-dropdown-toggle';
        toggle.type = 'button';

        const menu = document.createElement('ul');
        menu.className = 'nav-dropdown-menu';

        let activeLabel = null;
        exampleLinks.forEach(link => {
            const mli = document.createElement('li');
            const a = document.createElement('a');
            a.href = adjust(link.href);
            a.textContent = link.label;
            if (link.href.split('/').pop() === currentPage) {
                a.className = 'active';
                activeLabel = link.label;
            }
            mli.appendChild(a);
            menu.appendChild(mli);
        });

        toggle.textContent = (activeLabel || 'Examples') + ' ▾';

        toggle.addEventListener('click', (e) => {
            e.stopPropagation();
            li.classList.toggle('open');
        });
        document.addEventListener('click', () => li.classList.remove('open'));

        li.appendChild(toggle);
        li.appendChild(menu);
        ul.appendChild(li);

        // Insert after nav-brand
        const navBrand = navbar.querySelector('.nav-brand');
        if (navBrand) {
            navBrand.after(ul);
        } else {
            navbar.appendChild(ul);
        }
    },

    setupStatusIndicator() {
        const navbar = document.querySelector('.navbar');
        if (!navbar) return;

        // Add status indicator to navbar
        const statusEl = document.createElement('div');
        statusEl.className = 'nav-status';
        statusEl.innerHTML = `
            <span class="status-dot" id="navStatusDot"></span>
            <span id="navStatusText">Connecting...</span>
        `;
        navbar.appendChild(statusEl);

        // Update status on events
        this.on('onConnect', () => this.updateNavStatus('connected'));
        this.on('onDisconnect', () => this.updateNavStatus('disconnected'));
        this.on('onError', () => this.updateNavStatus('disconnected'));
    },

    updateNavStatus(status) {
        const dot = document.getElementById('navStatusDot');
        const text = document.getElementById('navStatusText');
        if (!dot || !text) return;

        dot.className = 'status-dot ' + status;
        text.textContent = status === 'connected' ? 'Connected' : 'Disconnected';
    }
};

// Auto-initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => MQTTClient.init());
