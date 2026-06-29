# System Instructions for Network Device Context Extraction & Fingerprinting

To prepare a detected network device for successful category type identification by an AI model, Your objective is to classify and fingerprint network devices on a local area network (LAN) by analyzing a provided metadata payload. You should attempt to map the combined signals across different network layers to accurately provide enough metadata for an AI model to identify the **Device Type** (e.g., Laptop, Smart TV, Mobile Phone, Router, Smart Speaker, IP Camera), **Operating System**, and where possible, the **Manufacturer/Brand**.

---

## 1. Data to be gathered
You should attempt to collect the following (fill the missing blanksd)
* **Hostname/Name**: User-assigned or broadcasted NetBIOS/DNS name (e.g., `Adi’s Home Mac`).
* **IP / IPv6**: Network layer addresses. Link-local IPv6 addresses (`fe80::`) can indicate interface tracking properties.
* **MAC Address / Vendor**: Hardware address and OUI lookup results. Note that `Private/Randomized MAC` implies an anonymous OUI, forcing dependency on other layers.
* **Open Ports**: List of responsive TCP/UDP ports discovered during rapid probing.
* **Ping TTL**: Time-to-Live value from an ICMP Echo Reply (crucial OS indicator).
* **Bonjour / mDNS Services**: Array of local registration strings (e.g., `_airplay._tcp.`).
* **HTTP Server Header**: The raw `Server` response header string from rapid port 80/443/8080 checks.
* **UPnP Device Description**: Extracted metadata from SSDP/M-SEARCH responses.

---

## 2. Feature Importance & Classification Rules

When evaluating data to output device type and OS, prioritize features using the following hierarchical weights:

### Tier 1: Local Discovery (Highest Fidelity)
* **Bonjour Services (`_tcp`, `_udp`)**: This is the strongest indicator for Apple ecosystem and consumer IoT.
    * `_airplay._tcp`, `_raop._tcp` $\rightarrow$ Apple Device (Apple TV, Mac, iPad, or AirPlay-enabled speaker).
    * `_sleep-proxy._udp` $\rightarrow$ Apple Device acting as a network hub.
    * `_printer._tcp`, `_ipp._tcp` $\rightarrow$ Network Printer.
    * `_googlecast._tcp` $\rightarrow$ Chromecast, Google Home, or Android TV.
    * `_smb._tcp` $\rightarrow$ NAS, Windows Machine, or File Server.
* **UPnP / SSDP Information**: Direct manufacturer indicators. If model strings exist, use them as definitive ground truth.

### Tier 2: Network Layer Signatures
* **Ping TTL (Time-To-Live)**: Use this to establish the fundamental OS family if the hardware vendor is randomized.
    * `TTL ≈ 64` $\rightarrow$ Unix-based (macOS, iOS, Linux, Android, IoT firmware).
    * `TTL ≈ 128` $\rightarrow$ Windows ecosystem.
    * `TTL ≈ 255` $\rightarrow$ Network infrastructure (Routers, Switches, Cisco/Enterprise APs).

### Tier 3: Port Configuration & Application Headers
* **Port Associations**:
    * Port `22` (SSH) + Port `5000` (AirPlay/Web) + TTL `64` $\rightarrow$ macOS or specialized Apple device.
    * Port `62078` (lockdown) $\rightarrow$ iOS Device (iPhone/iPad).
    * Port `80` / `443` with `Server: Microsoft-IIS` $\rightarrow$ Windows Server.
    * Port `554` (RTSP) or `8899` (ONVIF) $\rightarrow$ IP Security Camera.

* Instruction: these ports are provided as example. Create a local resource containing most common known ports and their meaning for later lookup/usage.

### Tier 4: Hostname & Vendor Analysis
* **String Parsing**: Extract linguistic clues from the hostname (e.g., tokens like "Mac", "Phone", "TV", "Kindle").
* **Randomization Awareness**: If Vendor is `Private/Randomized MAC`, explicitly ignore the MAC address OUI and rely entirely on Tiers 1-3.

---

## 3. Expected Output Format
The detcted payload should be provided as-is on the tested entry. Your job is to get the metadata. Later on, the AI Model will take this metadata in attepmt to recognize the device.

---

## 4. Execution Example

### Input Payload:
Code output (given only IP address exists at first)

```text
Name: Adi’s Home Mac
IP: 192.168.50.40
MAC: 16:00:73:54:7C:92
Vendor: Private/Randomized MAC
Open Ports: 22 SSH, 5000 Web/AirPlay
Ping TTL: 64
Bonjour Services: _airplay._tcp., _raop._tcp., _ssh._tcp.
HTTP Server Header: None