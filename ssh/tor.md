Diagrams Network :

```mermaid
graph TD;
1[SSH-Client]-->2[Stunnel4-TLS]-->3[TCP]-->4[SSH-Dropbear]-->6[TCP]-->7[VPS]-->8[SOCKS5]-->9[TOR]-->19[Internet];
1[SSH-Client]-->3[TCP]-->5[SSH-OpenSSH]-->6[TCP];
A[XRAY-Client]-->B[Nginx-TLS]-->C[TCP]-->D[Xray-CORE]-->E[TCP]-->F[VPS]-->G[SOCKS5]-->H[TOR]-->19[Internet];
11[OpenVPN-Client]-->12[TCP]-->15[OpenVPN-Server]-->23[TCP]-->16[VPS]-->17[SOCKS5]-->18[TOR]-->19[Internet];
11[OpenVPN-Client]-->13[UDP]-->15[OpenVPN-Server]-->21[UDP]-->16[VPS]-->22[UDP]-->19[Internet];
11[OpenVPN-Client]-->14[SSL]-->15[OpenVPN-Server];
```

Diagrams Network ASCII :

             ┌─────────────┐
             │   Client    │
             │ (SSH Client)│
             └──────┬──────┘
                    │
                    │ TLS/SSL (Port 777 / ... )
                    │
                    ▼
             ┌─────────────┐
             │  Stunnel    │
             │ (TLS Proxy) │
             └──────┬──────┘
                    │  Forward to internal SSH
                    │  (127.0.0.1:2222 / ... )
                    ▼
             ┌─────────────┐
             │   SSH /     │
             │ Dropbear    │
             └──────┬──────┘
                    │
                    │ (SSH traffic)
                    ▼
             ┌────────────────┐
             │  Tor           │
             │  TransPort     │
             │ 127.0.0.1:9040 │
             └──────┬─────────┘
                    │
                    ▼
             ┌─────────────┐
             │  Internet   │
             │ (via Tor)   │
             └─────────────┘

########################################################################################

             ┌─────────────┐
             │   Client    │
             │   (XRAY     │
             │  over TLS)  │
             └──────┬──────┘
                    │
                    │ TLS/SSL (Port 443 / ... )
                    │
                    ▼
             ┌─────────────┐
             │    Nginx    │
             │ (TLS Proxy) │
             └──────┬──────┘
                    │  Forward to internal Xray
                    │  (127.0.0.1:10001 / 10002 / ... )
                    ▼
             ┌─────────────┐
             │  Xray-CORE  │
             └──────┬──────┘
                    │
                    │ TCP traffic
                    ▼
             ┌────────────────┐
             │   Tor          │
             │  TransPort     │
             │ 127.0.0.1:9040 │
             └──────┬─────────┘
                    │
                    ▼
             ┌─────────────┐
             │  Internet   │
             │ (via Tor)   │
             └─────────────┘
