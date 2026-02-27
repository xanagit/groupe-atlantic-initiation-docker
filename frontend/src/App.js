import React, { useEffect, useState } from "react";

function App() {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    // Lecture de la variable d'environement BACKEND_URL injectée lors du démarrage
    const backendUrl = window.__ENV__?.BACKEND_URL || "";

    fetch(`${backendUrl}/`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then(setData)
      .catch((err) => setError(err.message));
  }, []);

  if (error) return <p>Error: {error}</p>;
  if (!data) return <p>Loading...</p>;

  return (
    <div>
      <h1>{data.title}</h1>
      <p><strong>Environment:</strong> {data.environment}</p>
      <p>{data.message}</p>
    </div>
  );
}

export default App;
