import requests

session = requests.Session()
session.headers.update({
    'x-api-key': "",
    'Content-Type': 'application/json'
})

labels = ['sexual', 'hate', 'violence', 'harassment', 'self-harm', 'sexual/minors', 'hate/threatening', 'violence/graphic']

while True:
    text = input("Input: ")
    
    response = session.post(
        "http://127.0.0.1:9235/run",
        json={'text': text},
        timeout=2
    )
    
    data = response.json()
    
    print("Predictions:")
    for label in labels:
        print(f"{label}: {data.get(label, 0.0):.2f}")