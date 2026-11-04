<script setup>
import { Sapling } from "@saplingai/sapling-js/observer";
import { ref, onMounted } from 'vue'

const editorRef = ref(null);

onMounted(() => {
  Sapling.init({
    key: '<YOUR_API_KEY>',
    endpointHostname: 'https://api.sapling.ai',
    editPathname: '/api/v1/edits',
    statusBadge: true,
    mode: 'dev',
  });

  Sapling.observe(editorRef.value);
})

// Shows an overall score and highlights the sentences flagged as AI-generated
function checkAI() {
  Sapling.checkOnce(editorRef.value, { aiDetect: true });
}
</script>

<template>
  <div id="editor" ref="editorRef" sapling-ignore="true" contenteditable>
    Lets get started! Phone chargers are essential accessories that have become an integral part of modern life. These devices are designed to replenish the battery life of our smartphones and other electronic gadgets, enabling us to stay connected and productive throughout the day. With advancements in technology, phone chargers have evolved significantly, offering various types such as wired, wireless, fast-charging, and portable chargers. The convenience and versatility of phone chargers have revolutionized the way we use our devices, ensuring we can always stay powered up and connected in our fast-paced, digital world.
  </div>
  <button id="ai-detect-button" @click="checkAI">Check AI</button>
</template>

<style scoped>
#editor{
  min-height: 200px;
  width:  400px;
  padding: 10px;
  margin: 10px;
  border: 1px solid;
}
#ai-detect-button{
  margin: 0 10px;
}
</style>
