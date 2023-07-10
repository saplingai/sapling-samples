<script setup>
import { Sapling } from "@saplingai/sapling-js/observer";
import { ref, onMounted } from 'vue'

const editorRef = ref(null);

onMounted(() => {
  console.log('onMounted');
  Sapling.init({
    key: '<API_KEY>',
    endpointHostname: 'https://api.sapling.ai',
    editPathname: '/api/v1/edits',
    statusBadge: true,
    mode: 'dev',
  });

  console.log('editorRef.value:', editorRef.value);
  Sapling.observe(editorRef.value);
})
</script>

<template>
  <div id="editor" ref="editorRef" sapling-ignore="true" contenteditable>
    Lets get started.
  </div>
</template>

<style scoped>
#editor{
  height: 200px;
  width:  400px;
  padding: 10px;
  margin: 10px;
  border: 1px solid;
}
</style>
