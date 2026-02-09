// Shared Whiteboard - Collaborative Drawing via MQTT
const Whiteboard = {
    canvas: null,
    ctx: null,
    wrapper: null,
    isDrawing: false,
    lastX: 0,
    lastY: 0,
    userId: 'user_' + Math.random().toString(36).substring(2, 8),
    color: '#0ea5e9',
    brushSize: 5,
    users: new Map(),
    cursors: new Map(),
    
    topics: {
        draw: 'whiteboard/draw',
        cursor: 'whiteboard/cursor',
        clear: 'whiteboard/clear',
        join: 'whiteboard/join',
        leave: 'whiteboard/leave'
    },

    init() {
        this.canvas = document.getElementById('whiteboard');
        this.ctx = this.canvas.getContext('2d');
        this.wrapper = document.getElementById('canvasWrapper');
        
        this.setupCanvas();
        this.setupControls();
        this.setupEventListeners();
        this.setupMQTT();
        
        // Handle page unload
        window.addEventListener('beforeunload', () => this.announceLeave());
    },

    setupCanvas() {
        // Set canvas to fill container width
        const containerWidth = this.wrapper.parentElement.clientWidth - 48;
        this.canvas.width = Math.min(containerWidth, 1000);
        this.canvas.height = 500;
        
        // Set default drawing style
        this.ctx.lineCap = 'round';
        this.ctx.lineJoin = 'round';
        this.ctx.strokeStyle = this.color;
        this.ctx.lineWidth = this.brushSize;
    },

    setupControls() {
        const colorPicker = document.getElementById('colorPicker');
        const brushSize = document.getElementById('brushSize');
        const brushSizeValue = document.getElementById('brushSizeValue');
        const clearBtn = document.getElementById('clearBtn');

        colorPicker.addEventListener('input', (e) => {
            this.color = e.target.value;
            this.ctx.strokeStyle = this.color;
            this.announceJoin(); // Update user color
        });

        brushSize.addEventListener('input', (e) => {
            this.brushSize = parseInt(e.target.value);
            this.ctx.lineWidth = this.brushSize;
            brushSizeValue.textContent = this.brushSize + 'px';
        });

        clearBtn.addEventListener('click', () => this.clearCanvas(true));
    },

    setupEventListeners() {
        // Mouse events
        this.canvas.addEventListener('mousedown', (e) => this.startDrawing(e));
        this.canvas.addEventListener('mousemove', (e) => this.draw(e));
        this.canvas.addEventListener('mouseup', () => this.stopDrawing());
        this.canvas.addEventListener('mouseout', () => this.stopDrawing());

        // Touch events for mobile
        this.canvas.addEventListener('touchstart', (e) => {
            e.preventDefault();
            const touch = e.touches[0];
            this.startDrawing(touch);
        });
        this.canvas.addEventListener('touchmove', (e) => {
            e.preventDefault();
            const touch = e.touches[0];
            this.draw(touch);
        });
        this.canvas.addEventListener('touchend', () => this.stopDrawing());

        // Track cursor position even when not drawing
        this.canvas.addEventListener('mousemove', (e) => this.sendCursorPosition(e));
    },

    setupMQTT() {
        MQTTClient.on('onConnect', () => {
            // Subscribe to whiteboard topics
            MQTTClient.subscribe(this.topics.draw);
            MQTTClient.subscribe(this.topics.cursor);
            MQTTClient.subscribe(this.topics.clear);
            MQTTClient.subscribe(this.topics.join);
            MQTTClient.subscribe(this.topics.leave);
            
            // Announce presence
            this.announceJoin();
        });

        MQTTClient.on('onMessage', (topic, payload) => {
            try {
                const data = JSON.parse(payload);
                
                // Ignore own messages for drawing (we draw locally)
                if (topic === this.topics.draw && data.userId !== this.userId) {
                    this.handleRemoteDraw(data);
                } else if (topic === this.topics.cursor && data.userId !== this.userId) {
                    this.handleRemoteCursor(data);
                } else if (topic === this.topics.clear) {
                    this.clearCanvas(false);
                } else if (topic === this.topics.join) {
                    this.handleUserJoin(data);
                } else if (topic === this.topics.leave) {
                    this.handleUserLeave(data);
                }
            } catch (e) {
                console.error('Error parsing whiteboard message:', e);
            }
        });
    },

    getCanvasCoords(e) {
        const rect = this.canvas.getBoundingClientRect();
        const scaleX = this.canvas.width / rect.width;
        const scaleY = this.canvas.height / rect.height;
        
        return {
            x: (e.clientX - rect.left) * scaleX,
            y: (e.clientY - rect.top) * scaleY
        };
    },

    startDrawing(e) {
        this.isDrawing = true;
        const coords = this.getCanvasCoords(e);
        this.lastX = coords.x;
        this.lastY = coords.y;
    },

    draw(e) {
        if (!this.isDrawing) return;

        const coords = this.getCanvasCoords(e);
        
        // Draw locally
        this.drawLine(this.lastX, this.lastY, coords.x, coords.y, this.color, this.brushSize);
        
        // Send to MQTT
        this.publishDraw(this.lastX, this.lastY, coords.x, coords.y);
        
        this.lastX = coords.x;
        this.lastY = coords.y;
    },

    stopDrawing() {
        this.isDrawing = false;
    },

    drawLine(x1, y1, x2, y2, color, size) {
        this.ctx.beginPath();
        this.ctx.strokeStyle = color;
        this.ctx.lineWidth = size;
        this.ctx.moveTo(x1, y1);
        this.ctx.lineTo(x2, y2);
        this.ctx.stroke();
        this.ctx.closePath();
    },

    publishDraw(x1, y1, x2, y2) {
        const data = {
            userId: this.userId,
            x1, y1, x2, y2,
            color: this.color,
            size: this.brushSize
        };
        MQTTClient.publish(this.topics.draw, JSON.stringify(data));
    },

    handleRemoteDraw(data) {
        this.drawLine(data.x1, data.y1, data.x2, data.y2, data.color, data.size);
    },

    sendCursorPosition(e) {
        const coords = this.getCanvasCoords(e);
        const rect = this.canvas.getBoundingClientRect();
        
        const data = {
            userId: this.userId,
            x: coords.x / this.canvas.width,  // Normalized 0-1
            y: coords.y / this.canvas.height,
            color: this.color
        };
        MQTTClient.publish(this.topics.cursor, JSON.stringify(data));
    },

    handleRemoteCursor(data) {
        let cursor = this.cursors.get(data.userId);
        
        if (!cursor) {
            cursor = this.createCursorElement(data.userId, data.color);
            this.cursors.set(data.userId, cursor);
        }
        
        // Update cursor position (convert normalized coords back to pixels)
        const rect = this.canvas.getBoundingClientRect();
        cursor.style.left = (data.x * rect.width) + 'px';
        cursor.style.top = (data.y * rect.height) + 'px';
        cursor.querySelector('.cursor-dot').style.backgroundColor = data.color;
        
        // Reset timeout to hide cursor after inactivity
        if (cursor.hideTimeout) clearTimeout(cursor.hideTimeout);
        cursor.style.opacity = '1';
        cursor.hideTimeout = setTimeout(() => {
            cursor.style.opacity = '0';
        }, 3000);
    },

    createCursorElement(userId, color) {
        const cursor = document.createElement('div');
        cursor.className = 'cursor';
        cursor.innerHTML = `
            <div class="cursor-dot" style="background-color: ${color}"></div>
            <div class="cursor-label">${userId.substring(0, 8)}</div>
        `;
        this.wrapper.appendChild(cursor);
        return cursor;
    },

    clearCanvas(broadcast = false) {
        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        
        if (broadcast) {
            MQTTClient.publish(this.topics.clear, JSON.stringify({ userId: this.userId }));
        }
    },

    announceJoin() {
        const data = {
            userId: this.userId,
            color: this.color,
            timestamp: Date.now()
        };
        MQTTClient.publish(this.topics.join, JSON.stringify(data));
        
        // Add self to users list
        this.users.set(this.userId, { color: this.color, isSelf: true });
        this.updateUsersList();
    },

    announceLeave() {
        const data = { userId: this.userId };
        MQTTClient.publish(this.topics.leave, JSON.stringify(data));
    },

    handleUserJoin(data) {
        this.users.set(data.userId, { 
            color: data.color, 
            isSelf: data.userId === this.userId 
        });
        this.updateUsersList();
        
        // If someone else joined, re-announce ourselves so they see us
        if (data.userId !== this.userId) {
            setTimeout(() => this.announceJoin(), 500);
        }
    },

    handleUserLeave(data) {
        this.users.delete(data.userId);
        
        // Remove cursor element
        const cursor = this.cursors.get(data.userId);
        if (cursor) {
            cursor.remove();
            this.cursors.delete(data.userId);
        }
        
        this.updateUsersList();
    },

    updateUsersList() {
        const usersList = document.getElementById('usersList');
        usersList.innerHTML = '';
        
        this.users.forEach((user, id) => {
            const badge = document.createElement('div');
            badge.className = 'user-badge' + (user.isSelf ? ' you' : '');
            badge.innerHTML = `
                <div class="user-color" style="background-color: ${user.color}"></div>
                <span class="user-name">${id.substring(0, 8)}${user.isSelf ? ' (you)' : ''}</span>
            `;
            usersList.appendChild(badge);
        });
    }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => Whiteboard.init());
