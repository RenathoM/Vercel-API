// Test different approaches to get Background category items
async function testBackgroundFilters() {
  const baseUrl = 'https://catalog.roblox.com/v1/search/items/details';
  
  const tests = [
    { name: 'Keyword "background"', params: '?keyword=background&limit=10' },
    { name: 'Keyword "Background"', params: '?keyword=Background&limit=10' },
    { name: 'Category Accessories with bg keyword', params: '?category=Accessories&keyword=background&limit=10' },
    { name: 'Subcategory Backgrounds', params: '?subcategory=Backgrounds&limit=10' },
    { name: 'Subcategory "AvatarBackgrounds"', params: '?subcategory=AvatarBackgrounds&limit=10' },
  ];
  
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
  };
  
  for (const test of tests) {
    try {
      const url = baseUrl + test.params;
      const response = await fetch(url, { headers });
      const data = await response.json();
      const count = data.data ? data.data.length : 0;
      
      console.log(`\n${test.name}:`);
      console.log(`  Items: ${count}`);
      
      if (count > 0) {
        console.log(`  First 2:`);
        data.data.slice(0, 2).forEach((item, i) => {
          console.log(`    ${i+1}. ${item.name}`);
        });
      }
    } catch (e) {
      console.log(`${test.name}: ERROR - ${e.message}`);
    }
  }
}

testBackgroundFilters();
