import 'react-native-url-polyfill/auto';
import {Platform} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {createClient} from '@supabase/supabase-js';

const url=process.env.EXPO_PUBLIC_SUPABASE_URL||'';
const key=process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY||'';

export const isSupabaseConfigured=Boolean(url&&key);
export const supabase=createClient(url,key,{auth:{storage:Platform.OS==='web'?undefined:AsyncStorage,autoRefreshToken:true,persistSession:true,detectSessionInUrl:false}});
