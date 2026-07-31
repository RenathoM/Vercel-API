// Direct test of Roblox API with subcategory
async function testDirect() {
  console.log('=== TESTING ROBLOX API DIRECTLY ===\n');
  
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
  };
  
  const tests = [
    { name: 'Subcategory=Backgrounds', url: 'https://catalog.roblox.com/v1/search/items/details?subcategory=Backgrounds&limit=10' },
    { name: 'Keyword=background', url: 'https://catalog.roblox.com/v1/search/items/details?keyword=background&limit=10' },
  ];
  
  for (const test of tests) {
    try {
      const response = await fetch(test.url, { headers });
      const data = await response.json();
      console.log(`${test.name}:`);
      console.log(`  Items: ${data.data.length}`);
      console.log(`  First 3:`);
      data.data.slice(0, 3).forEach((item, i) => {
        console.log(`    ${i+1}. ${item.name} (ID: ${item.id})`);
      });
      console.log('');
    } catch (e) {
      console.log(`ERROR: ${e.message}\n`);
    }
  }
}

testDirect();
