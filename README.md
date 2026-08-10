<h1 align="center">
NordiCoin
</h1>

<p align="center">
Open source BLE tracker with up to 6 years of battery life on a single coin cell.
</p>

<p align="center">
<img width="400" alt="image" src="https://github.com/user-attachments/assets/f9047588-bca1-4fa3-a6ba-e45a179871a7" />
</p>

<p align="center">
<img width="200" alt="image" src="https://github.com/user-attachments/assets/a2fcad10-c388-451f-8866-70268bd4eb0e" /> <img width="200" alt="image" src="https://github.com/user-attachments/assets/c5449b5d-c16f-4817-b4cf-026a9f9bcf0d" /> <img width="200" alt="image" src="https://github.com/user-attachments/assets/1b66e71f-f68b-43da-9919-f261593c09da" />
</p>

- It does not rely on a corporation BLE network to find it. Just you and your devices who track it. Dedicated android app and [watchy](https://github.com/Szybet/InkWatchy) support. The app alerts you once you are out of range
- Design focuses on easy self assembly by individuals
- Buzzer, to find it easier and a button to stop buzzing
- Wanna use it as a remote for home automation? Sure, that's possible
- Built using the nrf52805
- Firmware written in rust
- Further potential to improve battery life

### Licence
Open Community License v1.1 + General Attribution v1

### Contact
Github issues, [Yatchy discord server](https://github.com/Szybet/Yatchy), [Quill OS matrix space](https://quill-os.org)

### Power consumption
It's a spectrum, the absolute best I got was 3.7uA

<img height="500" alt="image" src="https://github.com/user-attachments/assets/39d11ed7-1051-45b8-bef5-feb2df012a93" />

But this, at least with the current method is hard to connect to because it's 5s of advertisement delay, not 4s. With 4, it's around 4.5uA. Explore the `battery_life.ods` file to confirm

If someone really wanted to, it would be possible to sync time, advertise only on full minute, make the app do the same and this way it would advertise 15 times less. 10 years of battery life easily achievable. But connecting to it, at least with regular android phones would take long/impossible. That's why I decided the current setup is good enough
