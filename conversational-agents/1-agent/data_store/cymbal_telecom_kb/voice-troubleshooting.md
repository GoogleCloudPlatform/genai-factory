# Voice Troubleshooting Guide

This document contains a comprehensive guide to troubleshooting common voice-related issues encountered by Cymbal Telecom customers.

## 1. No Audio / Dead Air

*   **Problem Statement:** The customer reports that they cannot hear anyone, and/or the other party cannot hear them, resulting in complete silence or "dead air" on a call. This applies to both inbound and outbound calls.

*   **Troubleshooting Steps:**
    *   **1.1. Device and Connection Check:**
        *   **Verify** the customer's phone or device is properly connected and powered on.
        *   **Check** if the audio is muted on the device (e.g., volume turned down, mute button active).
        *   **Confirm** the speaker/headset is working by testing with another audio source if possible.
        *   **Ask** the customer to restart their phone/device.
    *   **1.2. Network Status Assessment:**
        *   **Check** the customer's internet connection status. Is their broadband working?
        *   **Confirm** other internet services (web browsing, email) are functional.
        *   **Test** if the issue is isolated to Cymbal Telecom's service or affects all internet-based communication.
    *   **1.3. Service Status and Account:**
        *   **Consult** internal service status dashboards for any known outages in the customer's area.
        *   **Verify** the customer's account is active and in good standing (not suspended for billing issues).
        *   **Check** if the voice service feature is enabled on their plan.
    *   **1.4. Port Forwarding / NAT (if applicable):**
        *   For customers using VoIP adapters (ATAs) or IP phones behind their own router, **advise** them to check their router's NAT settings and ensure SIP/RTP ports are not being blocked. (Refer to `Networking - Customer Router Configuration` document).
    *   **1.5. Test Call:**
        *   **Initiate** a test call to a known working number (e.g., Cymbal Telco support line, a different mobile phone).
        *   **Ask** the customer to call their own number from an external line.
    *   **1.6. Escalation:**
        *   If all basic checks fail, **escalate** to Level 2 Support for network diagnostics and backend system checks.

## 2. One-Way Audio

*   **Problem Statement:** The customer can hear the other party, but the other party cannot hear them (or vice-versa). Audio flows only in one direction.

*   **Troubleshooting Steps:**
    *   **2.1. Device Microphone/Speaker Check:**
        *   **Confirm** the customer's microphone is not muted or malfunctioning.
        *   **Ask** them to try another microphone or headset if available.
        *   **Listen** for any background noise from the customer's end that might suggest a faulty microphone.
    *   **2.2. Network Address Translation (NAT) Issues:**
        *   **Explain** that one-way audio often points to NAT traversal issues in the customer's router/firewall.
        *   **Suggest** checking the router's SIP ALG (Application Layer Gateway) setting and **disabling** it if enabled. SIP ALG can often interfere with VoIP.
        *   **Recommend** ensuring proper port forwarding for RTP (Real-time Transport Protocol) ports if using a dedicated IP phone or ATA. (Refer to `Networking - Advanced VoIP Configurations`).
    *   **2.3. Firewall Configuration:**
        *   **Inquire** if the customer has any software firewalls on their computer (if using a softphone) or security appliances that might be blocking outgoing or incoming RTP traffic.
        *   **Advise** temporarily disabling the firewall for testing purposes (and re-enabling it after).
    *   **2.4. Bandwidth and Jitter:**
        *   While less common for one-way, insufficient upload or download bandwidth, or high jitter, can sometimes manifest as one-way audio if packets are being dropped consistently in one direction.
        *   **Perform** a basic internet speed test.
    *   **2.5. Call Flow Trace:**
        *   If the issue persists, **document** details (caller ID, called ID, time, duration) for Level 2 support to perform a call trace and analyze signaling and media paths.

## 3. Poor Audio Quality / Static / Choppy Audio

*   **Problem Statement:** The customer reports that voice calls are breaking up, sound robotic, contain static, or are excessively noisy.

*   **Troubleshooting Steps:**
    *   **3.1. Internet Connection Stability:**
        *   **Check** the customer's internet connection for stability issues. Are there any noticeable fluctuations or packet loss?
        *   **Advise** disconnecting other high-bandwidth devices on the network (streaming, large downloads) during the call.
        *   **Run** a speed test and a ping test to `8.8.8.8` to check for latency and packet loss. A sustained packet loss over 1% can severely impact call quality.
    *   **3.2. Wi-Fi Interference (if applicable):**
        *   If the customer is on Wi-Fi, **suggest** trying a wired connection if possible to rule out wireless interference or signal strength issues.
        *   **Recommend** moving closer to the Wi-Fi router or trying a different Wi-Fi channel if the router supports it.
    *   **3.3. Router QoS (Quality of Service) Settings:**
        *   **Explain** the importance of QoS for VoIP traffic.
        *   **Advise** the customer to check if their router has QoS settings enabled and if VoIP traffic is prioritized. (Refer to `Networking - Router QoS Setup Guide`).
    *   **3.4. Codec Mismatch/Preferred Codec:**
        *   Less common for residential users, but for business customers with specific IP phones, **inquire** if they have preferred codecs enabled that might be causing issues. G.711 (PCMU/PCMA) generally requires more bandwidth but less processing; G.729 (default for many) is compressed but can be more sensitive to packet loss.
    *   **3.5. Equipment Check:**
        *   **Ask** the customer to try a different phone, handset, or headset to rule out faulty hardware.
        *   **Check** physical cabling for damage or loose connections.
    *   **3.6. Power Cycle Equipment:**
        *   **Instruct** the customer to power cycle their modem, router, and VoIP adapter/IP phone in sequence (modem first, then router, then phone/adapter).

## 4. Excessive Audio Latency / Delay

*   **Problem Statement:** The customer reports noticeable delays during conversations, making it difficult to have natural conversation ("talking over each other"). This is often described as an "echo" if delayed audio from the other end is heard back.

*   **Troubleshooting Steps:**
    *   **4.1. Network Congestion:**
        *   **Check** background network activity. Are other devices on the customer's network consuming significant bandwidth (streaming, gaming, large downloads/uploads)?
        *   **Suggest** suspending or reducing these activities during calls.
    *   **4.2. Router Processing Power / QoS:**
        *   **Inquire** about the customer's router. An older or lower-end router might struggle to process VoIP packets efficiently, especially under load, leading to latency.
        *   **Reinforce** the importance of correctly configured QoS settings to prioritize voice traffic (as per section 3.3).
    *   **4.3. Internet Route Latency:**
        *   While often outside direct control, **perform** a trace route to relevant Cymbal Telecom IP addresses (e.g., `traceroute voip.cymbaltelecom.com` or an IP provided by Level 2 support). Look for high latency hops.
        *   If high latency is identified within Cymbal's network, **escalate** for network operations team review.
    *   **4.4. Device Processing Delay:**
        *   For some VoIP devices or softphones, internal processing can add minor delays. **Suggest** testing with a different device if available.
    *   **4.5. Echo Cancellation:**
        *   If the reported "echo" is clearly the customer's own voice delayed, it's often a network latency issue. If it's the *other party's* voice echoing back, it might be an echo cancellation function on the *other party's* side or excessive speaker volume on the customer's side. **Advise** reducing speaker volume if that's the case.

## 5. Incorrect Billing for Voice Calls

*   **Problem Statement:** The customer reports that a voice call was incorrectly charged, or they were charged for a call they did not make.

*   **Troubleshooting Steps:**
    *   **5.1. Review Call Detail Records (CDRs):**
        *   **Access** the customer's account and retrieve the call detail records for the disputed period.
        *   **Compare** the customer's recollection of calls with the system logs.
        *   **Confirm** the date, time, duration, and dialed number for the disputed calls.
    *   **5.2. Plan and Rate Review:**
        *   **Verify** the customer's current voice call plan and included/excluded features (e.g., unlimited local, long-distance minutes, international call bundles).
        *   **Check** the rates for international calls, premium numbers, or calls outside their plan. (Refer to `Rates - Voice Call Rate Sheet` document).
    *   **5.3. Premium / Directory / Information Numbers:**
        *   **Inquire** if the disputed calls are to known premium rate numbers (e.g., 1-900 numbers, specific directory services). These are often billed separately at higher rates.
    *   **5.4. International Calls:**
        *   **Confirm** if the customer made international calls. International rates vary significantly by destination.
        *   **Check** if the customer used a dialing access code for international calls.
    *   **5.5. Auto-Dialers / Unwanted Calls:**
        *   **Ask** if anyone else has access to their phone line or if they have any equipment that might automatically dial numbers.
        *   **Check** for potential phone fraud or unwanted calls if charges are for numbers the customer claims not to have dialed *at all*. (Elevate to security team if fraud is suspected).
    *   **5.6. System Error Check:**
        *   If the CDRs clearly show a discrepancy or a call that seems impossible (e.g., 24-hour duration for a short call), **flag** this for Level 2 Billing Support or the Billing Operations team for an internal system audit. This might indicate a metering or logging error.
    *   **5.7. Credit/Adjustment:**
        *   If a clear billing error originating from Cymbal Telecom is identified, **process** a credit adjustment as per policy, after internal verification.
