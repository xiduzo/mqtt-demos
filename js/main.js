// Main application logic
document.addEventListener('DOMContentLoaded', () => {
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');
    const connectBtn = document.getElementById('connectBtn');
    const disconnectBtn = document.getElementById('disconnectBtn');

    function updateStatus(status) {
        statusDot.className = 'status-dot ' + status;
        switch(status) {
            case 'connected':
                statusText.textContent = 'Connected';
                connectBtn.disabled = true;
                disconnectBtn.disabled = false;
                break;
            case 'connecting':
                statusText.textContent = 'Connecting...';
                connectBtn.disabled = true;
                disconnectBtn.disabled = true;
                break;
            default:
                statusText.textContent = 'Disconnected';
                connectBtn.disabled = false;
                disconnectBtn.disabled = true;
        }
    }

    MQTTClient.on('onConnect', () => updateStatus('connected'));
    MQTTClient.on('onDisconnect', () => updateStatus('disconnected'));
    MQTTClient.on('onError', () => updateStatus('disconnected'));

    connectBtn.addEventListener('click', () => {
        updateStatus('connecting');
        MQTTClient.connect();
    });

    disconnectBtn.addEventListener('click', () => {
        MQTTClient.disconnect();
    });
});
